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
                subscriber.yield(objects)
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
    }
    
    public func load(
        context: LoadContext<Object?>,
        continuation: LoadContinuation<Object?>
    ) {
        let container = self.container
        let fetchRequest = self.fetchRequest
        
        Task { @MainActor in
            let context = container.viewContext
            // Mimic SingleObjectFetcher init logic: limit 1
            let request = fetchRequest.copy() as! NSFetchRequest<Object>
            request.fetchLimit = 1
            
            do {
                let results = try context.fetch(request)
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
                subscriber.yield(object)
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
        self.childRequest = child
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
                subscriber.yield(groupedObjects)
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

// SAFETY: This is a dangerous conformance required for 'swift-sharing' interoperability.
// NSManagedObjects are NOT thread-safe. They must ONLY be accessed on the actor they were created on (here, @MainActor).
// The library fetchers are isolated to @MainActor, so as long as these values are consumed on MainActor, it is safe-ish.
// Accessing properties of these objects on a background thread WILL cause a crash or data corruption.
extension NSManagedObject: @unchecked @retroactive Sendable {}
extension NSPredicate: @unchecked @retroactive Sendable {}
extension KeyPath: @unchecked @retroactive Sendable where Root: Sendable, Value: Sendable {}
extension NSFetchRequest: @unchecked @retroactive Sendable {}
