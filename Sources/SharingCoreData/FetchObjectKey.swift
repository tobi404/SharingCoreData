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
        descriptors: [NSSortDescriptor] = [],
        relationshipKeyPathsForPrefetching: [String] = [],
        batchSize: Int? = nil
    ) -> Self
    where Self == FetchAllObjectKey<Value>.Default {
        Self[
            FetchAllObjectKey(
                for: object,
                predicate: predicate,
                sort: descriptors,
                relationshipKeyPathsForPrefetching: relationshipKeyPathsForPrefetching,
                batchSize: batchSize
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
    
    public static func fetchGrouped<Parent: NSManagedObject, Child: NSManagedObject>(
        groupRequest: NSFetchRequest<Parent>,
        childRequest: @escaping @Sendable (Parent) -> NSFetchRequest<Child>
    ) -> Self
    where Self == FetchGroupedObjectKey<Parent, Child>.Default {
        Self[
            FetchGroupedObjectKey(
                group: groupRequest,
                child: childRequest
            ),
            default: [:]
        ]
    }
}

// MARK: - FetchAll

public struct FetchAllObjectKey<Object: NSManagedObject>: SharedReaderKey {
    private let container: NSPersistentContainer
    private let fetchRequest: NSFetchRequest<Object>
    private let objectFetcher: ObjectFetcher<Object>
    
    public typealias Value = [Object]
    public typealias ID = FetchRequestID
    
    public var id: ID {
        FetchRequestID(from: fetchRequest)
    }
    
    init(
        for object: Object.Type,
        predicate: NSPredicate? = nil,
        sort: [NSSortDescriptor],
        relationshipKeyPathsForPrefetching: [String],
        batchSize: Int? = nil
    ) {
        @Dependency(\.persistentContainer) var container
        
        let fetchRequest = Object.fetchRequest() as! NSFetchRequest<Object>
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sort
        fetchRequest.relationshipKeyPathsForPrefetching = relationshipKeyPathsForPrefetching
        
        if let batchSize {
            fetchRequest.fetchBatchSize = batchSize
        }
        
        self.container = container
        self.fetchRequest = fetchRequest
        self.objectFetcher = ObjectFetcher<Object>(
            fetchRequest: fetchRequest,
            context: container.viewContext
        )
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
    private let container: NSPersistentContainer
    private let fetchRequest: NSFetchRequest<Object>
    private let objectFetcher: SingleObjectFetcher<Object>
    
    public typealias Value = Object?
    public typealias ID = FetchRequestID
    
    public var id: ID {
        FetchRequestID(from: fetchRequest)
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
    private let fetchRequest: NSFetchRequest<Object>
    private let countFetcher: ObjectCountFetcher<Object>
    
    public typealias Value = Int
    public typealias ID = FetchRequestID
    
    public var id: ID {
        FetchRequestID(from: fetchRequest)
    }
    
    init(
        for object: Object.Type,
        predicate: NSPredicate? = nil
    ) {
        @Dependency(\.persistentContainer) var container
        
        let fetchRequest = Object.fetchRequest() as! NSFetchRequest<Object>
        fetchRequest.predicate = predicate
        
        self.container = container
        self.fetchRequest = fetchRequest
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

// MARK: - FetchGrouped

public struct FetchGroupedObjectKey<Parent: NSManagedObject, Child: NSManagedObject>: SharedReaderKey {
    private let container: NSPersistentContainer
    private let parentRequest: NSFetchRequest<Parent>
    private let objectFetcher: GroupedObjectFetcher<Parent, Child>
    
    public typealias Value = [Parent: [Child]]
    public typealias ID = FetchRequestID
    
    public var id: ID {
        FetchRequestID(from: parentRequest)
    }
    
    init(
        group parent: NSFetchRequest<Parent>,
        child: @escaping @Sendable (Parent) -> NSFetchRequest<Child>
    ) {
        @Dependency(\.persistentContainer) var container
        
        self.container = container
        self.parentRequest = parent
        self.objectFetcher = GroupedObjectFetcher<Parent, Child>(groupRequest: parent, childRequest: child, context: container.viewContext)
    }
    
    public func load(
        context: LoadContext<[Parent: [Child]]>,
        continuation: LoadContinuation<[Parent: [Child]]>
    ) {
        Task {
            let groupedObjects = await objectFetcher.groupedObjects()
            continuation.resume(returning: groupedObjects)
        }
    }
    
    public func subscribe(
        context: LoadContext<[Parent: [Child]]>,
        subscriber: SharedSubscriber<[Parent: [Child]]>
    ) -> SharedSubscription {
        Task {
            for await groupedObjects in await objectFetcher.groupedObjectsStream {
                subscriber.yield(groupedObjects)
            }
        }
        
        return SharedSubscription {
            Task {
                await objectFetcher.cancelStream()
            }
        }
    }
}

// MARK: - FetchRequestID

public struct FetchRequestID: Hashable {
    // Core properties that define what data is fetched
    fileprivate let entityName: String
    fileprivate let predicateFormat: String?
    fileprivate let sortDescriptorRepresentations: [SortDescriptorRepresentation]
    
    // Helper struct for sort descriptors
    fileprivate struct SortDescriptorRepresentation: Hashable {
        let key: String?
        let ascending: Bool
        
        init(from sortDescriptor: NSSortDescriptor) {
            self.key = sortDescriptor.key
            self.ascending = sortDescriptor.ascending
        }
    }
    
    // Initialize from an NSFetchRequest
    public init<T: NSFetchRequestResult>(from fetchRequest: NSFetchRequest<T>) {
        self.entityName = fetchRequest.entityName ?? ""
        
        // Handle predicate
        self.predicateFormat = fetchRequest.predicate?.predicateFormat

        // Handle sort descriptors
        if let sortDescriptors = fetchRequest.sortDescriptors {
            self.sortDescriptorRepresentations = sortDescriptors.map {
                SortDescriptorRepresentation(from: $0)
            }
        } else {
            self.sortDescriptorRepresentations = []
        }
    }
}

// MARK: - Core Data sendability

extension NSManagedObject: @unchecked @retroactive Sendable {}
extension NSPredicate: @unchecked @retroactive Sendable {}
extension KeyPath: @unchecked Sendable where Root: Sendable, Value: Sendable {}
