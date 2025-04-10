//
//  FetchedResultsControllerWrapper.swift
//  sharing-CoreData
//
//  Created by Beka Demuradze on 10.04.25.
//

@preconcurrency import CoreData

/// A generic wrapper for NSFetchedResultsController that provides closure callbacks
/// for changes in managed objects.
actor FetchedResultsControllerWrapper<T: NSManagedObject>: NSObject, NSFetchedResultsControllerDelegate {
    
    // MARK: - Properties
    
    /// The underlying NSFetchedResultsController.
    private var fetchedResultsController: NSFetchedResultsController<T>
    
    /// Closure called when an object is updated.
    var objectUpdated: ((T) -> Void)?
    
    /// Closure called when an object is inserted.
    var objectInserted: ((T) -> Void)?
    
    /// Closure called when an object is deleted.
    var objectDeleted: ((T) -> Void)?
    
    /// Closure called when an object is moved.
    /// Provides the object, original indexPath, and new indexPath.
    var objectMoved: ((T, IndexPath, IndexPath) -> Void)?
    
    // MARK: - Initializer
    
    /// Initializes the wrapper with a fetch request, context, and optional section name and cache.
    /// - Parameters:
    ///   - fetchRequest: The NSFetchRequest for the managed object type T.
    ///   - context: The NSManagedObjectContext to operate on.
    ///   - sectionNameKeyPath: An optional section name key path.
    ///   - cacheName: An optional cache name.
    init(
        fetchRequest: NSFetchRequest<T>,
        context: NSManagedObjectContext,
        sectionNameKeyPath: String? = nil,
        cacheName: String? = nil,
        objectUpdated: @escaping ((T) -> Void),
        objectInserted: @escaping ((T) -> Void),
        objectDeleted: @escaping ((T) -> Void),
        objectMoved: @escaping ((T, IndexPath, IndexPath) -> Void)
    ) {
        fetchedResultsController = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: context,
            sectionNameKeyPath: sectionNameKeyPath,
            cacheName: cacheName
        )
        super.init()
        self.objectUpdated = objectUpdated
        self.objectInserted = objectInserted
        self.objectDeleted = objectDeleted
        self.objectMoved = objectMoved
        
        // Set the delegate for the NSFetchedResultsController.
        fetchedResultsController.delegate = self
        
        // Perform the initial fetch
        do {
            try fetchedResultsController.performFetch()
        } catch {
            reportIssue("Error performing initial fetch: \(error)")
        }
    }
    
    // MARK: - Public Accessors
    
    /// Access to the currently fetched objects.
    var objects: [T]? {
        fetchedResultsController.fetchedObjects
    }
    
    func stop() {
        fetchedResultsController.delegate = nil
    }
    
    // MARK: - NSFetchedResultsControllerDelegate Methods
    
    /// Tells the delegate that a fetched object has been changed due to an add, remove, move, or update.
    private func controller(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>,
        didChange anObject: Any,
        at indexPath: IndexPath?,
        for type: NSFetchedResultsChangeType,
        newIndexPath: IndexPath?
    ) async {
        // Cast the changed object to the generic type.
        guard let object = anObject as? T else { return }
        
        // Handle changes based on the type.
        switch type {
        case .insert:
            objectInserted?(object)
        case .delete:
            objectDeleted?(object)
        case .update:
            objectUpdated?(object)
        case .move:
            // Ensure both old and new index paths are valid.
            if let oldIndexPath = indexPath, let newIndexPath = newIndexPath {
                objectMoved?(object, oldIndexPath, newIndexPath)
            }
        @unknown default:
            break
        }
    }
    
    // Optionally, if you want to notify after all changes have been applied.
    private func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) async {
        // For example, you might refresh a UI list here.
        // This method is optional if you want a "batch update" callback.
    }
}
