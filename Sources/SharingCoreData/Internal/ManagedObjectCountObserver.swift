//
//  ManagedObjectCountObserver.swift
//  sharing-core-data
//
//  Created by Beka Demuradze on 14.04.25.
//

@preconcurrency import CoreData

final class ObserverHolder<T: NSManagedObject>: @unchecked Sendable {
    var observer: ManagedObjectCountObserver<T>?
    
    func getOrCreateObserver(
        context: NSManagedObjectContext,
        predicate: NSPredicate?
    ) async -> ManagedObjectCountObserver<T> {
        if let observer = observer {
            return observer
        }
        let newObserver = await ManagedObjectCountObserver<T>(context: context, predicate: predicate)
        observer = newObserver
        return newObserver
    }
}

@MainActor
final class ManagedObjectCountObserver<T: NSManagedObject> {
    var count: Int {
        currentCount
    }
    private var context: NSManagedObjectContext
    private var predicate: NSPredicate?
    private var notificationToken: NSObjectProtocol?
    private var currentCount: Int = 0
    private var onChange: ((Int) -> Void)?
    
    // MARK: - Initialization
    
    /// Initializes the observer with a context, predicate, and change handler.
    /// - Parameters:
    ///   - context: The managed object context to observe.
    ///   - predicate: The predicate to filter objects of type T.
    ///   - onChange: Closure to invoke with the new count whenever it changes.
    init(context: NSManagedObjectContext, predicate: NSPredicate?) {
        self.context = context
        self.predicate = predicate
    }
    
    deinit {
        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
        }
    }
    
    func startObserving(onChange: @escaping (Int) -> Void) {
        self.onChange = onChange
        
        updateCount(notifyAlways: true)
        
        notificationToken = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: context,
            queue: .main
        ) { [weak self] notification in
            Task {
                await self?.handleContextChange(notification: notification)
            }
        }
    }
    
    func stopObserving() {
        onChange = nil
        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
        }
    }
    
    // MARK: - Private Methods
    
    /// Handles context change notifications by determining if a relevant change occurred.
    private func handleContextChange(notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        // Check if any inserted/deleted/updated objects are of type T
        if let inserts = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>,
           inserts.contains(where: { $0 is T }) {
            updateCount()
            return
        }
        if let deletes = userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject>,
           deletes.contains(where: { $0 is T }) {
            updateCount()
            return
        }
        if let updates = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject>,
           updates.contains(where: { $0 is T }) {
            // For updates, the object may have changed such that it now matches or no longer matches the predicate
            updateCount()
            return
        }
        // (You could also handle NSRefreshedObjectsKey or others if needed, omitted for brevity)
    }
    
    /// Performs the count fetch and invokes the callback if needed.
    private func updateCount(notifyAlways: Bool = false) {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: String(describing: T.self))
        fetchRequest.predicate = self.predicate
        fetchRequest.resultType = .countResultType
        fetchRequest.includesSubentities = false  // Count only this entity (no sub-entity objects)
        
        // Execute the count request
        var newCount: Int = 0
        do {
            newCount = try context.count(for: fetchRequest)
        } catch {
            reportIssue("⚠️ CoreData count fetch error: \(error)")
            newCount = 0
        }
        
        // If count changed (or we need to notify always on first fetch), call the handler
        if notifyAlways || newCount != self.currentCount {
            self.currentCount = newCount
            self.onChange?(newCount)
        }
    }
}
