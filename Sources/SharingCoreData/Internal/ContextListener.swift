//
//  ContextListener.swift
//  sharing-core-data
//
//  Created by Beka Demuradze on 24.04.25.
//

import Dependencies
@preconcurrency import CoreData
@preconcurrency import CloudKit

private let persistentHistoryTokenKey = "PersistentHistoryToken"

@MainActor
final class ContextListener<T: NSManagedObject>: Sendable {
    // MARK: - Types

    enum ChangeType: Sendable {
        case inserted
        case deleted
        case updated
    }
    
    // MARK: - Properties

    private let onChange: @Sendable (ChangeType) -> Void
    private let context: NSManagedObjectContext
    private var notificationToken: NSObjectProtocol?
    private var forceRefreshToken: NSObjectProtocol?
    private var cloudKitSyncToken: NSObjectProtocol?
    private var lastTokenData: Data?
    private var throttleTask: Task<Void, Never>?
    
    // MARK: - Initialization

    @MainActor
    init(
        context: NSManagedObjectContext,
        onChange: @Sendable @escaping (ChangeType) -> Void
    ) {
        self.context = context
        self.onChange = onChange
        self.startObserving()
    }
    
    deinit {
        throttleTask?.cancel()

        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
        }
        
        if let token = forceRefreshToken {
            NotificationCenter.default.removeObserver(token)
        }
        
        if let token = cloudKitSyncToken {
            NotificationCenter.default.removeObserver(token)
        }
    }
    
    // MARK: - Setup

    private func startObserving() {
        let context = self.context
        let onChangeHandler = self.onChange
        let observedEntityName = String(describing: T.self)
        
        notificationToken = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: context,
            queue: .main
        ) { [weak self] notification in
            guard self != nil else { return }
            let insertedIDs = (notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>)?
                .map(\.objectID) ?? []
            let deletedIDs = (notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject>)?
                .map(\.objectID) ?? []
            let updatedIDs = (notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject>)?
                .map(\.objectID) ?? []
            
            if let changeType = Self.determineChangeType(
                entityName: observedEntityName,
                insertedIDs: insertedIDs,
                deletedIDs: deletedIDs,
                updatedIDs: updatedIDs
            ) {
                onChangeHandler(changeType)
            }
        }
        
        forceRefreshToken = NotificationCenter.default.addObserver(
            forName: .forceReloadData,
            object: nil,
            queue: .main
        ) { _ in
            onChangeHandler(.updated)
        }
        
        if #available(iOS 14.0, *) {
            cloudKitSyncToken = NotificationCenter.default.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let event = notification
                    .userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event
                else {
                    return
                }
                
                // event.endDate != nil means this import/export phase has finished
                let finished = (event.endDate != nil) && event.succeeded
                switch (event.type, finished) {
                case (.import, true):
                    Task {
                        await self?.processPersistentHistory()
                    }
                default:
                    break
                }
            }
        }
    }
    
    // MARK: - Change Classification

    nonisolated private static func determineChangeType(
        entityName: String,
        insertedIDs: [NSManagedObjectID],
        deletedIDs: [NSManagedObjectID],
        updatedIDs: [NSManagedObjectID]
    ) -> ChangeType? {
        if insertedIDs.contains(where: { $0.entity.name == entityName }) {
            return .inserted
        }
        
        if deletedIDs.contains(where: { $0.entity.name == entityName }) {
            return .deleted
        }
        
        if updatedIDs.contains(where: { $0.entity.name == entityName }) {
            return .updated
        }
        
        return nil
    }
    
    // MARK: - Persistent History

    @available(iOS 14.0, *)
    private func processPersistentHistory() async {
        @Dependency(\.persistentContainer) var container
        
        guard let storeURL = container.persistentStoreCoordinator.persistentStores.first?.url else {
            print("Failed to fetch history: missing persistent store.")
            return
        }

        let backgroundContext = container.newBackgroundContext()
        let previousTokenData = self.lastTokenData ?? loadHistoryTokenData()
        
        do {
            let (changeTypes, newTokenData): ([ChangeType], Data?) =
                try await withCheckedThrowingContinuation { continuation in
                    backgroundContext.perform {
                        do {
                            let token: NSPersistentHistoryToken?
                            if let previousTokenData {
                                token = try? NSKeyedUnarchiver.unarchivedObject(
                                    ofClass: NSPersistentHistoryToken.self,
                                    from: previousTokenData
                                )
                            } else {
                                token = nil
                            }

                            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
                            if let matchingStore = backgroundContext.persistentStoreCoordinator?.persistentStores.first(
                                where: { $0.url == storeURL }
                            ) {
                                request.affectedStores = [matchingStore]
                            }

                            let result = try backgroundContext.execute(request) as? NSPersistentHistoryResult
                            guard let transactions = result?.result as? [NSPersistentHistoryTransaction] else {
                                continuation.resume(returning: ([], previousTokenData))
                                return
                            }

                            var changeTypes: [ChangeType] = []
                            let entityName = String(describing: T.self)
                            for transaction in transactions {
                                for change in transaction.changes ?? [] {
                                    guard change.changedObjectID.entity.name == entityName else { continue }
                                    switch change.changeType {
                                    case .insert:
                                        changeTypes.append(.inserted)
                                    case .update:
                                        changeTypes.append(.updated)
                                    case .delete:
                                        changeTypes.append(.deleted)
                                    @unknown default:
                                        break
                                    }
                                }
                            }

                            let tokenData: Data?
                            if let newToken = transactions.last?.token {
                                tokenData = try NSKeyedArchiver.archivedData(
                                    withRootObject: newToken,
                                    requiringSecureCoding: true
                                )
                            } else {
                                tokenData = previousTokenData
                            }
                            continuation.resume(returning: (changeTypes, tokenData))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
            }

            for changeType in changeTypes {
                throttleChange(changeType)
            }

            self.lastTokenData = newTokenData
            saveHistoryTokenData(newTokenData)
        } catch {
            print("Failed to fetch history: \(error)")
        }
    }
    
    // MARK: - Throttling

    private func throttleChange(_ changeType: ChangeType) {
        throttleTask?.cancel() // Cancel previous task
        throttleTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: NSEC_PER_SEC * 1)
                self?.onChange(changeType)
                print("💬 AfterThrottle:", changeType)
            } catch {
                // Task cancelled, ignore
            }
        }
    }
    
    // MARK: - Token Persistence

    private func saveHistoryTokenData(_ tokenData: Data?) {
        guard let tokenData else {
            UserDefaults.standard.removeObject(forKey: persistentHistoryTokenKey)
            return
        }

        UserDefaults.standard.set(tokenData, forKey: persistentHistoryTokenKey)
    }

    private func loadHistoryTokenData() -> Data? {
        UserDefaults.standard.data(forKey: persistentHistoryTokenKey)
    }
}

// MARK: - Notifications

public extension Notification.Name {
    static let forceReloadData = Notification.Name("force_reload_data")
}
