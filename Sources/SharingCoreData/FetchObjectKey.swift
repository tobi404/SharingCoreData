//
//  FetchObjectKey.swift
//  sharing-CoreData
//
//  Created by Beka Demuradze on 10.04.25.
//

import Sharing
@preconcurrency import CoreData

extension SharedReaderKey {
    public static func fetch<Value: NSManagedObject & Identifiable>(
        for object: Value.Type,
        predicate: NSPredicate? = nil
    ) -> Self
    where Self == FetchOneObjectKey<Value>.Default {
        Self[
            FetchOneObjectKey(
                for: object,
                predicate: predicate,
                sort: nil
            ),
            default: nil
        ]
    }
    
    public static func fetchAll<Value: NSManagedObject>(
        for object: Value.Type,
        predicate: NSPredicate? = nil,
        sort: NSSortDescriptor
    ) -> Self
    where Self == FetchAllObjectKey<Value>.Default {
        Self[
            FetchAllObjectKey(
                for: object,
                predicate: predicate,
                sort: [sort]
            ),
            default: []
        ]
    }
    
    public static func fetchAll<Value: NSManagedObject>(
        for object: Value.Type,
        predicate: NSPredicate? = nil,
        sort: [NSSortDescriptor]
    ) -> Self
    where Self == FetchAllObjectKey<Value>.Default {
        Self[
            FetchAllObjectKey(
                for: object,
                predicate: predicate,
                sort: sort
            ),
            default: []
        ]
    }
    
    public static func fetchCount<Value: NSManagedObject>(
        for object: Value.Type,
        predicate: NSPredicate? = nil
    ) -> Self
    where Self == FetchCountKey<Value>.Default {
        Self[
            FetchCountKey(
                for: object,
                predicate: predicate
            ),
            default: 0
        ]
    }
}

// MARK: - FetchAll

public struct FetchAllObjectKey<Object: NSManagedObject>: SharedReaderKey {
    let container: NSPersistentContainer
    let fetchRequest: NSFetchRequest<Object>
    var controller: FetchedResultsControllerWrapper<Object>?
    
    public typealias Value = [Object]
    public typealias ID = FetchKeyID
    
    public var id: ID {
        FetchKeyID(
            description: fetchRequest.description,
            objectName: fetchRequest.entity?.name ?? ""
        )
    }
    
    init(
        for object: Object.Type,
        predicate: NSPredicate? = nil,
        sort: [NSSortDescriptor]
    ) {
        @Dependency(\.persistentContainer) var container
        
        let fetchRequest = Object.fetchRequest() as! NSFetchRequest<Object>
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sort
        
        self.container = container
        self.fetchRequest = fetchRequest
        self.controller = FetchedResultsControllerWrapper<Object>(
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
            continuation.resume(returning: objects)
        }
    }
    
    public func subscribe(
        context: LoadContext<[Object]>,
        subscriber: SharedSubscriber<[Object]>
    ) -> SharedSubscription {
        Task {
            await controller?.observeValueChange { objects in
                subscriber.yield(objects)
            }
        }
        
        return SharedSubscription {
            Task {
                await controller?.cancelValueChangeObservation()
            }
        }
    }
}

// MARK: - FetchOne

public struct FetchOneObjectKey<Object: NSManagedObject & Identifiable>: SharedReaderKey {
    let container: NSPersistentContainer
    let fetchRequest: NSFetchRequest<Object>
    let store = ObjectStore<Object>()
    var controller: FetchedResultsControllerWrapper<Object>?
    
    public typealias Value = Object?
    public typealias ID = FetchKeyID
    
    public var id: ID {
        FetchKeyID(
            description: fetchRequest.description,
            objectName: fetchRequest.entity?.name ?? ""
        )
    }
    
    init(
        for object: Object.Type,
        predicate: NSPredicate? = nil,
        sort: NSSortDescriptor? = nil
    ) {
        @Dependency(\.persistentContainer) var container
        
        let fetchRequest = Object.fetchRequest() as! NSFetchRequest<Object>
        fetchRequest.predicate = predicate
        if let sort {
            fetchRequest.sortDescriptors = [sort]
        } else {
            fetchRequest.sortDescriptors = []
        }
        
        self.container = container
        self.fetchRequest = fetchRequest
        self.controller = FetchedResultsControllerWrapper<Object>(
            fetchRequest: fetchRequest,
            managedObjectContext: container.viewContext
        )
    }
    
    public func load(
        context: LoadContext<Object?>,
        continuation: LoadContinuation<Object?>
    ) {
        Task {
            if let object = await controller?.objects.last {
                store.object = object
                continuation.resume(returning: object)
            } else {
                continuation.resumeReturningInitialValue()
            }
        }
    }
    
    public func subscribe(
        context: LoadContext<Object?>,
        subscriber: SharedSubscriber<Object?>
    ) -> SharedSubscription {
        Task {
            await controller?.observeValueChange { objects in
                guard let object = objects.first(where: { $0.id == store.object?.id }) else {
                    subscriber.yieldReturningInitialValue()
                    return
                }
                subscriber.yield(object)
            }
        }
        
        return SharedSubscription {
            Task {
                await controller?.cancelValueChangeObservation()
            }
        }
    }
}

// MARK: - FetchCount

public struct FetchCountKey<Object: NSManagedObject>: SharedReaderKey {
    let container: NSPersistentContainer
    let predicate: NSPredicate?
    private let observerHolder = ObserverHolder<Object>()

    public typealias Value = Int
    public typealias ID = FetchKeyID
    
    public var id: ID {
        let objectName = String(describing: Object.self)
        return FetchKeyID(
            description: predicate?.description ?? objectName,
            objectName: objectName
        )
    }
    
    init(
        for object: Object.Type,
        predicate: NSPredicate? = nil
    ) {
        @Dependency(\.persistentContainer) var container
        
        self.container = container
        self.predicate = predicate
    }
    
    public func load(
        context: LoadContext<Int>,
        continuation: LoadContinuation<Int>
    ) {
        Task {
            let observer = await observerHolder.getOrCreateObserver(
                context: container.viewContext,
                predicate: predicate
            )
            continuation.resume(returning: await observer.count)
        }
    }
    
    public func subscribe(
        context: LoadContext<Int>,
        subscriber: SharedSubscriber<Int>
    ) -> SharedSubscription {
        Task {
            let observer = await observerHolder.getOrCreateObserver(context: container.viewContext, predicate: predicate)
            
            await observer.startObserving() { count in
                subscriber.yield(count)
            }
        }
        
        return SharedSubscription {
            Task {
                let observer = await observerHolder.getOrCreateObserver(context: container.viewContext, predicate: predicate)
                await observer.stopObserving()
            }
        }
    }
}

class ObjectStore<Object: NSManagedObject & Identifiable>: @unchecked Sendable {
    var object: Object?
}

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
extension NSPredicate: @unchecked @retroactive Sendable {}

