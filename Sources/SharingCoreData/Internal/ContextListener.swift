//
//  ContextListener.swift
//  sharing-core-data
//
//  Created by Beka Demuradze on 24.04.25.
//

@preconcurrency import CoreData

actor ContextListener<T: NSManagedObject>: Sendable {
    enum ChangeType: Sendable {
        case inserted
        case deleted
        case updated
    }
    
    private let onChange: @Sendable (ChangeType) -> Void
    private let context: NSManagedObjectContext
    private var notificationToken: NSObjectProtocol?
    
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
}
