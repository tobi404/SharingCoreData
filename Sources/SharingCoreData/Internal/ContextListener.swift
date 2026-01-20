//
//  ContextListener.swift
//  sharing-core-data
//
//  Created by Beka Demuradze on 24.04.25.
//

import Dependencies
@preconcurrency import CoreData
@preconcurrency import CloudKit

actor ContextListener<T: NSManagedObject>: Sendable {
    enum ChangeType: Sendable {
        case inserted
        case deleted
        case updated
    }
    
    private let onChange: @Sendable (ChangeType) -> Void
    private let context: NSManagedObjectContext
    private var notificationToken: NSObjectProtocol?
    private var forceRefreshToken: NSObjectProtocol?
    private var cloudKitSyncToken: NSObjectProtocol?
    private var lastToken: NSPersistentHistoryToken?
    private var throttleTask: Task<Void, Never>? // Throttling task
    
    init(
        context: NSManagedObjectContext,
        onChange: @Sendable @escaping (ChangeType) -> Void
    ) {
        self.context = context
        self.onChange = onChange
        Task { await self.startObserving() }
    }
    
    deinit {
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
    
    private func startObserving() {
        let context = self.context
        let onChangeHandler = self.onChange
        
        notificationToken = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: context,
            queue: nil
        ) { [weak self] notification in
            guard let self = self else { return }
            
            Task {
                if let changeType = await self.processContextChange(notification: notification) {
                    onChangeHandler(changeType)
                }
            }
        }
        
        forceRefreshToken = NotificationCenter.default.addObserver(
            forName: .forceReloadData,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self = self else { return }
            
            Task {
                onChangeHandler(.updated)
            }
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
                        await self?.processPersistentHistory(for: event)
                    }
                default:
                    break
                }
            }
        }
    }
    
    private func processContextChange(notification: Notification) -> ChangeType? {
        guard let userInfo = notification.userInfo else { return nil }
        
        // Check if any inserted/deleted/updated objects are of type T
        if
            let inserts = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>,
            inserts.contains(where: { $0 is T })
        {
            return .inserted
        }
        
        if
            let deletes = userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject>,
            deletes.contains(where: { $0 is T })
        {
            return .deleted
        }
        
        if
            let updates = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject>,
            updates.contains(where: { $0 is T })
        {
            return .updated
        }
        
        return nil
    }
    
    @available(iOS 14.0, *)
    private func processPersistentHistory(for event: NSPersistentCloudKitContainer.Event) {
        @Dependency(\.persistentContainer) var container
        
        let storeIdentifier = event.storeIdentifier
        let backgroundContext = container.newBackgroundContext()
        let lastToken = self.lastToken ?? loadHistoryToken()
        
        backgroundContext.performAndWait {
            @Dependency(\.persistentContainer) var container
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: lastToken)
            request.affectedStores = [container.persistentStoreCoordinator.persistentStores.first!]
            
            do {
                let result = try backgroundContext.execute(request) as? NSPersistentHistoryResult
                guard let transactions = result?.result as? [NSPersistentHistoryTransaction] else { return }
                
                for transaction in transactions {
                    for change in transaction.changes ?? [] {
                        let objectID = change.changedObjectID
                        
                        // Get the entity name (e.g., "User" or "Post")
                        let entityName = objectID.entity.name ?? "Unknown"
                        
                        guard entityName == String(describing: T.self) else { continue }
                        
                        Task {
                            switch change.changeType {
                            case .insert:
                                await throttleChange(.inserted)
                            case .update:
                                await throttleChange(.updated)
                            case .delete:
                                await throttleChange(.deleted)
                            @unknown default:
                                break
                            }
                        }
                    }
                }
                
                if let newToken = transactions.last?.token {
                    Task {
                        await self.lastToken = newToken
                        await self.saveHistoryToken(newToken)
                    }
                }
            } catch {
                print("Failed to fetch history: \(error)")
            }
        }
    }
    
    private func throttleChange(_ changeType: ChangeType) {
        throttleTask?.cancel() // Cancel previous task
        throttleTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: NSEC_PER_SEC * 1)
                await self?.onChange(changeType)
                print("💬 AfterThrottle:", changeType)
            } catch {
                // Task cancelled, ignore
            }
        }
    }
    
    private func saveHistoryToken(_ token: NSPersistentHistoryToken?) {
        guard let token = token else {
            UserDefaults.standard.removeObject(forKey: "PersistentHistoryToken")
            return
        }

        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: token,
                requiringSecureCoding: true
            )
            UserDefaults.standard.set(data, forKey: "PersistentHistoryToken")
        }
        catch {
            print("🔴 Failed to archive history token:", error)
        }
    }

    // MARK: – Loading

    private func loadHistoryToken() -> NSPersistentHistoryToken? {
        guard let data = UserDefaults.standard.data(forKey: "PersistentHistoryToken") else {
            return nil
        }

        do {
            return try NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSPersistentHistoryToken.self,
                from: data
            )
        }
        catch {
            print("🔴 Failed to unarchive history token:", error)
            return nil
        }
    }
}

public extension Notification.Name {
    static let forceReloadData = Notification.Name("force_reload_data")
}

@available(iOS 14.0, *)
extension NSPersistentCloudKitContainer.Event: @unchecked @retroactive Sendable {}
