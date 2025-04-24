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
    let objectFetcher: ObjectFetcher<Object>
    
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
        self.objectFetcher = ObjectFetcher<Object>(fetchRequest: fetchRequest, context: container.viewContext)
    }
    
    public func load(
        context: LoadContext<[Object]>,
        continuation: LoadContinuation<[Object]>
    ) {
        Task {
            let objects = await objectFetcher.objects()
            continuation.resume(returning: objects)
        }
    }
    
    public func subscribe(
        context: LoadContext<[Object]>,
        subscriber: SharedSubscriber<[Object]>
    ) -> SharedSubscription {
        Task {
            for await objects in await objectFetcher.objectsStream {
                subscriber.yield(objects)
            }
        }
        
        return SharedSubscription {
            Task {
                await objectFetcher.cancelStream()
            }
        }
    }
}

// MARK: - FetchOne

public struct FetchOneObjectKey<Object: NSManagedObject & Identifiable>: SharedReaderKey {
    let container: NSPersistentContainer
    let fetchRequest: NSFetchRequest<Object>
    let objectFetcher: SingleObjectFetcher<Object>
    
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
        self.objectFetcher = SingleObjectFetcher(
            fetchRequest: fetchRequest,
            context: container.viewContext
        )
    }
    
    public func load(
        context: LoadContext<Object?>,
        continuation: LoadContinuation<Object?>
    ) {
        Task {
            if let object = await objectFetcher.object() {
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
            for await object in await objectFetcher.objectStream {
                subscriber.yield(object)
            }
        }
        
        return SharedSubscription {
            Task {
                await objectFetcher.cancelStream()
            }
        }
    }
}

// MARK: - FetchCount

public struct FetchCountKey<Object: NSManagedObject>: SharedReaderKey {
    private let container: NSPersistentContainer
    private let predicate: NSPredicate?
    private let countFetcher: ObjectCountFetcher<Object>

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
        let fetchRequest = NSFetchRequest<Object>()
        fetchRequest.predicate = predicate
        self.countFetcher = ObjectCountFetcher(fetchRequest: fetchRequest, context: container.viewContext)
    }
    
    public func load(
        context: LoadContext<Int>,
        continuation: LoadContinuation<Int>
    ) {
        Task {
            let count = await countFetcher.count()
            continuation.resume(returning: count)
        }
    }
    
    public func subscribe(
        context: LoadContext<Int>,
        subscriber: SharedSubscriber<Int>
    ) -> SharedSubscription {
        Task {
            for await count in await countFetcher.countStream {
                subscriber.yield(count)
            }
        }
        
        return SharedSubscription {
            Task {
                await countFetcher.cancelStream()
            }
        }
    }
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

