//
//  FetchedResultsControllerWrapper.swift
//  sharing-CoreData
//
//  Created by Beka Demuradze on 10.04.25.
//

@preconcurrency import CoreData

actor FetchedResultsControllerWrapper<T: NSManagedObject>: NSObject {
    var objects: [T] {
        _objects
    }
    
    private let fetchedResultsController: NSFetchedResultsController<T>
    private let delegate = FetchedResultsControllerDelegate<T>()
    private var onValueChanged: (([T]) -> Void)?
    private var _objects: [T] = []
    
    init(fetchRequest: NSFetchRequest<T>, managedObjectContext: NSManagedObjectContext) {
        fetchedResultsController = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: managedObjectContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        
        super.init()
        
        fetchedResultsController.delegate = delegate
        
        do {
            try fetchedResultsController.performFetch()
            _objects = fetchedResultsController.fetchedObjects ?? []
        } catch {
            reportIssue("Error performing initial fetch: \(error)")
        }
    }
    
    func observeValueChange(_ onValueChanged: @escaping ([T]) -> Void) {
        self.delegate.onValueChanged = onValueChanged
    }
    
    func cancelValueChangeObservation() {
        self.delegate.onValueChanged = nil
    }
}

final class FetchedResultsControllerDelegate<T: NSManagedObject>: NSObject, NSFetchedResultsControllerDelegate {
    var onValueChanged: (([T]) -> Void)?
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        guard let objects = controller.fetchedObjects as? [T] else { return }
        onValueChanged?(objects)
    }
}
