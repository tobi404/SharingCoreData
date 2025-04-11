//
//  FetchObjectKey.swift
//  sharing-CoreData
//
//  Created by Beka Demuradze on 10.04.25.
//

import Combine
@preconcurrency import CoreData

extension SharedReaderKey {
    @MainActor
    public static func fetchAll<Value: NSManagedObject>(
        for object: Value.Type,
        predicate: NSPredicate? = nil,
        sort: NSSortDescriptor
    ) -> Self
    where Self == FetchAllObjectKey<Value> {
        FetchAllObjectKey(
            for: object,
            predicate: predicate,
            sort: sort
        )
    }
}

public struct FetchAllObjectKey<Object: NSManagedObject>: SharedReaderKey {
    let container: NSPersistentContainer
    let fetchRequest: NSFetchRequest<Object>
    var controller: GenericFetchedResultsController<Object>?
    
    public typealias Value = [Object]
    public typealias ID = FetchKeyID
    
    public var id: ID {
        FetchKeyID(
            description: fetchRequest.description,
            objectName: fetchRequest.entity?.name ?? ""
        )
    }
    
    @MainActor
    init(
        for object: Object.Type,
        predicate: NSPredicate? = nil,
        sort: NSSortDescriptor? = nil
    ) {
        @Dependency(\.defaultContainer) var container
        
        let fetchRequest = Object.fetchRequest() as! NSFetchRequest<Object>
        fetchRequest.predicate = predicate
        if let sort {
            fetchRequest.sortDescriptors = [sort]
        }
        
        self.container = container
        self.fetchRequest = fetchRequest
        self.controller = GenericFetchedResultsController<Object>(
            fetchRequest: fetchRequest,
            managedObjectContext: container.viewContext
        )
    }
    
    public func load(
        context: LoadContext<[Object]>,
        continuation: LoadContinuation<[Object]>
    ) {
        Task {
            guard let objects = await controller?.objects else { return }
            await continuation.resume(returning: objects)
        }
    }
    
    public func subscribe(
        context: LoadContext<[Object]>,
        subscriber: SharedSubscriber<[Object]>
    ) -> SharedSubscription {
        Task {
            await controller?.setOnValueChanged { objects in
                subscriber.yield(objects)
            }
        }
        
        return SharedSubscription {
            Task {
                await controller?.cancelValueChange()
            }
        }
    }
}

/// A value that uniquely identifies a fetch key.
public struct FetchKeyID: Hashable {
    fileprivate let description: String
    fileprivate let objectName: String
    
    fileprivate init(
        description: String,
        objectName: String
    ) {
        self.description = description
        self.objectName = objectName
    }
}

extension NSManagedObject: @unchecked @retroactive Sendable {}

