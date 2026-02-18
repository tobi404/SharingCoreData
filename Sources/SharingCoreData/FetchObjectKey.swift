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
        childRequest: @escaping @Sendable (Parent) -> NSFetchRequest<Child>,
        fileID: StaticString = #fileID,
        line: UInt = #line
    ) -> Self
    where Self == FetchGroupedObjectKey<Parent, Child>.Default {
        Self[
            FetchGroupedObjectKey(
                group: groupRequest,
                child: childRequest,
                groupingIdentity: "\(fileID):\(line)"
            ),
            default: [:]
        ]
    }
}

// MARK: - FetchAll

public struct FetchAllObjectKey<Object: NSManagedObject>: SharedReaderKey {
    private let container: NSPersistentContainer
    private let fetchRequest: NSFetchRequest<Object>
    
    public typealias Value = [Object]
    public typealias ID = FetchRequestID
    
    public var id: ID {
        FetchRequestID(from: fetchRequest, queryKind: "all")
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
    }
    
    public func load(
        context: LoadContext<[Object]>,
        continuation: LoadContinuation<[Object]>
    ) {
        let container = self.container
        let fetchRequest = self.fetchRequest
        
        Task { @MainActor in
            let context = container.viewContext
            do {
                let objects = try context.fetch(fetchRequest)
                continuation.resume(returning: objects)
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
    
    public func subscribe(
        context: LoadContext<[Object]>,
        subscriber: SharedSubscriber<[Object]>
    ) -> SharedSubscription {
        let container = self.container
        let fetchRequest = self.fetchRequest
        
        let task = Task { @MainActor in
            let objectFetcher = ObjectFetcher<Object>(
                fetchRequest: fetchRequest,
                context: container.viewContext
            )
            for await objects in objectFetcher.objectsStream {
                subscriber.yield(objects.value)
            }
        }
        
        return SharedSubscription {
            task.cancel()
        }
    }
}

// MARK: - FetchOne

public struct FetchOneObjectKey<Object: NSManagedObject & Identifiable>: SharedReaderKey {
    private let container: NSPersistentContainer
    private let fetchRequest: NSFetchRequest<Object>
    
    public typealias Value = Object?
    public typealias ID = FetchRequestID
    
    public var id: ID {
        FetchRequestID(from: fetchRequest, queryKind: "one")
    }
    
    init(
        for object: Object.Type,
        predicate: NSPredicate? = nil,
        sort: NSSortDescriptor? = nil
    ) {
        @Dependency(\.persistentContainer) var container
        
        let fetchRequest = Object.fetchRequest() as! NSFetchRequest<Object>
        fetchRequest.predicate = predicate
        fetchRequest.fetchLimit = 1
        
        if let sort {
            fetchRequest.sortDescriptors = [sort]
        } else {
            fetchRequest.sortDescriptors = []
        }
        
        self.container = container
        self.fetchRequest = fetchRequest
    }
    
    public func load(
        context: LoadContext<Object?>,
        continuation: LoadContinuation<Object?>
    ) {
        let container = self.container
        let fetchRequest = self.fetchRequest
        
        Task { @MainActor in
            let context = container.viewContext
            do {
                let results = try context.fetch(fetchRequest)
                if let object = results.first {
                    continuation.resume(returning: object)
                } else {
                    continuation.resumeReturningInitialValue()
                }
            } catch {
                continuation.resumeReturningInitialValue()
            }
        }
    }
    
    public func subscribe(
        context: LoadContext<Object?>,
        subscriber: SharedSubscriber<Object?>
    ) -> SharedSubscription {
        let container = self.container
        let fetchRequest = self.fetchRequest
        
        let task = Task { @MainActor in
            let objectFetcher = SingleObjectFetcher(
                fetchRequest: fetchRequest,
                context: container.viewContext
            )
            for await object in objectFetcher.objectStream {
                subscriber.yield(object.value)
            }
        }
        
        return SharedSubscription {
            task.cancel()
        }
    }
}

// MARK: - FetchCount

public struct FetchCountKey<Object: NSManagedObject>: SharedReaderKey {
    private let container: NSPersistentContainer
    private let fetchRequest: NSFetchRequest<Object>
    
    public typealias Value = Int
    public typealias ID = FetchRequestID
    
    public var id: ID {
        FetchRequestID(from: fetchRequest, queryKind: "count")
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
    }
    
    public func load(
        context: LoadContext<Int>,
        continuation: LoadContinuation<Int>
    ) {
        let container = self.container
        let fetchRequest = self.fetchRequest
        
        Task { @MainActor in
            let context = container.viewContext
            let countRequest = fetchRequest.copy() as! NSFetchRequest<Object>
            countRequest.resultType = .countResultType
            
            do {
                let count = try context.count(for: countRequest)
                continuation.resume(returning: count)
            } catch {
                continuation.resume(returning: 0)
            }
        }
    }
    
    public func subscribe(
        context: LoadContext<Int>,
        subscriber: SharedSubscriber<Int>
    ) -> SharedSubscription {
        let container = self.container
        let fetchRequest = self.fetchRequest
        
        let task = Task { @MainActor in
            let countFetcher = ObjectCountFetcher(
                fetchRequest: fetchRequest,
                context: container.viewContext
            )
            for await count in countFetcher.countStream {
                subscriber.yield(count)
            }
        }
        
        return SharedSubscription {
            task.cancel()
        }
    }
}

// MARK: - FetchGrouped

public struct FetchGroupedObjectKey<Parent: NSManagedObject, Child: NSManagedObject>: SharedReaderKey {
    private let container: NSPersistentContainer
    private let parentRequest: NSFetchRequest<Parent>
    private let childRequest: @Sendable (Parent) -> NSFetchRequest<Child>
    private let groupingIdentity: String
    
    public typealias Value = [Parent: [Child]]
    public typealias ID = FetchRequestID
    
    public var id: ID {
        FetchRequestID(
            from: parentRequest,
            queryKind: "grouped",
            groupedChildIdentity: groupingIdentity
        )
    }
    
    init(
        group parent: NSFetchRequest<Parent>,
        child: @escaping @Sendable (Parent) -> NSFetchRequest<Child>,
        groupingIdentity: String
    ) {
        @Dependency(\.persistentContainer) var container
        
        self.container = container
        self.parentRequest = parent
        self.childRequest = child
        self.groupingIdentity = groupingIdentity
    }
    
    public func load(
        context: LoadContext<[Parent: [Child]]>,
        continuation: LoadContinuation<[Parent: [Child]]>
    ) {
        let container = self.container
        let parentRequest = self.parentRequest
        let childRequest = self.childRequest
        
        Task { @MainActor in
            let context = container.viewContext
            do {
                var group = [Parent: [Child]]()
                let results = try context.fetch(parentRequest)
                for result in results {
                    let cRequest = childRequest(result)
                    let children = try context.fetch(cRequest)
                    group[result] = children
                }
                continuation.resume(returning: group)
            } catch {
                continuation.resume(returning: [:])
            }
        }
    }
    
    public func subscribe(
        context: LoadContext<[Parent: [Child]]>,
        subscriber: SharedSubscriber<[Parent: [Child]]>
    ) -> SharedSubscription {
        let container = self.container
        let parentRequest = self.parentRequest
        let childRequest = self.childRequest
        
        let task = Task { @MainActor in
            let objectFetcher = GroupedObjectFetcher<Parent, Child>(
                groupRequest: parentRequest,
                childRequest: childRequest,
                context: container.viewContext
            )
            for await groupedObjects in objectFetcher.groupedObjectsStream {
                subscriber.yield(groupedObjects.value)
            }
        }
        
        return SharedSubscription {
            task.cancel()
        }
    }
}

// MARK: - FetchRequestID

public struct FetchRequestID: Hashable {
    // Core properties that define what data is fetched
    fileprivate let entityName: String
    fileprivate let predicateFormat: String?
    fileprivate let sortDescriptorRepresentations: [SortDescriptorRepresentation]
    fileprivate let fetchLimit: Int
    fileprivate let fetchOffset: Int
    fileprivate let fetchBatchSize: Int
    fileprivate let includesPendingChanges: Bool
    fileprivate let returnsObjectsAsFaults: Bool
    fileprivate let relationshipKeyPathsForPrefetching: [String]
    fileprivate let queryKind: String
    fileprivate let groupedChildIdentity: String?
    
    // Helper struct for sort descriptors
    fileprivate struct SortDescriptorRepresentation: Hashable {
        let key: String?
        let ascending: Bool
        let selector: String?
        let descriptor: String
        
        init(from sortDescriptor: NSSortDescriptor) {
            self.key = sortDescriptor.key
            self.ascending = sortDescriptor.ascending
            self.selector = sortDescriptor.selector.map(NSStringFromSelector)
            self.descriptor = String(describing: sortDescriptor)
        }
    }
    
    // Initialize from an NSFetchRequest
    public init<T: NSFetchRequestResult>(from fetchRequest: NSFetchRequest<T>) {
        self.init(from: fetchRequest, queryKind: "all", groupedChildIdentity: nil)
    }

    init<T: NSFetchRequestResult>(
        from fetchRequest: NSFetchRequest<T>,
        queryKind: String,
        groupedChildIdentity: String? = nil
    ) {
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

        self.fetchLimit = fetchRequest.fetchLimit
        self.fetchOffset = fetchRequest.fetchOffset
        self.fetchBatchSize = fetchRequest.fetchBatchSize
        self.includesPendingChanges = fetchRequest.includesPendingChanges
        self.returnsObjectsAsFaults = fetchRequest.returnsObjectsAsFaults
        self.relationshipKeyPathsForPrefetching = fetchRequest.relationshipKeyPathsForPrefetching ?? []
        self.queryKind = queryKind
        self.groupedChildIdentity = groupedChildIdentity
    }
}
