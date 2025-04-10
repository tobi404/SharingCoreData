//
//  FetchObjectKey.swift
//  sharing-CoreData
//
//  Created by Beka Demuradze on 10.04.25.
//

@preconcurrency import CoreData

extension SharedReaderKey {
    public static func fetchOne<Value: NSManagedObject>(
        for object: Value.Type,
        predicate: NSPredicate? = nil,
        sort: NSSortDescriptor? = nil
    ) -> Self
    where Self == FetchObjectKey<Value> {
        FetchObjectKey(
            for: object,
            predicate: predicate,
            sort: sort
        )
    }
}

public struct FetchObjectKey<Value: NSManagedObject>: SharedReaderKey {
    @Dependency(\.defaultContainer) var container
    let fetchRequest: NSFetchRequest<Value>
    
    public typealias ID = FetchKeyID
    
    public var id: ID {
        FetchKeyID(
            description: fetchRequest.description,
            objectName: fetchRequest.entity?.name ?? ""
        )
    }
    
    init(
        for object: Value.Type,
        predicate: NSPredicate? = nil,
        sort: NSSortDescriptor? = nil
    ) {
        let fetchRequest = NSFetchRequest<Value>()
        fetchRequest.predicate = predicate
        if let sort {
            fetchRequest.sortDescriptors = [sort]
        }
        self.fetchRequest = fetchRequest
    }
    
    public func load(
        context: LoadContext<Value>,
        continuation: LoadContinuation<Value>
    ) {
        do {
            guard let data = try container.viewContext.fetch(fetchRequest).first else {
                return continuation.resumeReturningInitialValue()
            }
            
            return continuation.resume(
                returning: data
            )
        } catch {
            return continuation.resumeReturningInitialValue()
        }
    }
    
    public func subscribe(
        context: LoadContext<Value>,
        subscriber: SharedSubscriber<Value>
    ) -> SharedSubscription {
        let fetchListener = FetchedResultsControllerWrapper<Value>(
            fetchRequest: fetchRequest,
            context: container.viewContext,
            objectUpdated: { object in
                subscriber.yield(object)
            },
            objectInserted: { object in
                reportIssue("Object insertion called")
            },
            objectDeleted: { object in
                subscriber.yieldReturningInitialValue()
            },
            objectMoved: { _,_,_ in
                reportIssue("objectMoved called")
            }
        )
        
        return SharedSubscription {
            Task {
                await fetchListener.stop()
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
