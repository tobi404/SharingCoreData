//
//  FetchedResultsControllerWrapper.swift
//  sharing-CoreData
//
//  Created by Beka Demuradze on 10.04.25.
//

@preconcurrency import CoreData
import Combine

@MainActor
final class GenericFetchedResultsController<T: NSManagedObject>: NSObject, @preconcurrency NSFetchedResultsControllerDelegate {
    let fetchedResultsController: NSFetchedResultsController<T>
    private var _objects: [T] = []
    var objects: [T] {
        _objects
    }
    var onValueChanged: (([T]) -> Void)?
    
    init(fetchRequest: NSFetchRequest<T>, managedObjectContext: NSManagedObjectContext) {
        fetchedResultsController = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: managedObjectContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        
        super.init()
        
        fetchedResultsController.delegate = self
        
        do {
            try fetchedResultsController.performFetch()
            _objects = fetchedResultsController.fetchedObjects ?? []
        } catch {
            print("Error performing initial fetch: \(error)")
        }
    }
    
    func setOnValueChanged(_ onValueChanged: @escaping ([T]) -> Void) {
        self.onValueChanged = onValueChanged
    }
    
    func cancelValueChange() {
        self.onValueChanged = nil
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        _objects = fetchedResultsController.fetchedObjects as? [T] ?? []
        onValueChanged?(_objects)
    }
}
