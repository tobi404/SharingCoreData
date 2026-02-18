//
//  SingleObjectFetcher.swift
//  sharing-core-data
//
//  Created by Beka Demuradze on 24.04.25.
//

@preconcurrency import CoreData

@MainActor
final class SingleObjectFetcher<T: NSManagedObject & Identifiable>: Sendable {
    // MARK: - Properties
    var objectStream: AsyncStream<UnsafeSendableValue<T?>> {
        if let _objectStream {
            return _objectStream
        }
        
        var continuation: AsyncStream<UnsafeSendableValue<T?>>.Continuation!
        let stream = AsyncStream<UnsafeSendableValue<T?>> { cont in
            continuation = cont
            // Send initial nil
            cont.yield(UnsafeSendableValue(value: nil))
        }
        
        self._objectStream = stream
        self.continuation = continuation
        return stream
    }
    
    private let fetchRequest: NSFetchRequest<T>
    private let context: NSManagedObjectContext
    private var listener: ContextListener<T>?
    
    // AsyncStream properties
    private var continuation: AsyncStream<UnsafeSendableValue<T?>>.Continuation?
    private var isStreamActive = true
    private var _objectStream: AsyncStream<UnsafeSendableValue<T?>>?
    
    // Current value cache
    private var currentObject: T?
    
    // MARK: - Initialization
    
    @MainActor
    init(
        fetchRequest: NSFetchRequest<T>,
        context: NSManagedObjectContext
    ) {
        // Ensure we're only fetching one object
        let limitedRequest = fetchRequest.copy() as! NSFetchRequest<T>
        limitedRequest.fetchLimit = 1
        
        self.fetchRequest = limitedRequest
        self.context = context
        
        Task {
            _ = self.objectStream
            await self.setupListener()
            await self.fetch()
        }
    }
    
    // MARK: - Setup
    
    private func setupListener() async {
        let contextListener = ContextListener<T>(
            context: context
        ) { [weak self] changeType in
            guard let self = self else { return }
            
            Task { @MainActor in
                switch changeType {
                case .inserted, .updated:
                    // Refetch the object on insert or update
                    await self.fetch()
                case .deleted:
                    // Refetch to avoid reacting to unrelated deletes of the same entity type.
                    await self.fetch()
                }
            }
        }
        
        self.listener = contextListener
    }
    
    private func setToNil() {
        self.currentObject = nil
        self.continuation?.yield(UnsafeSendableValue(value: nil))
    }
    
    private func setObject(_ newValue: T?) {
        currentObject = newValue
    }
    
    // MARK: - Fetching
    
    func fetch() async {
        guard isStreamActive else { return }
        
        do {
            let results = try context.fetch(fetchRequest)
            let object = results.first
            
            // Only yield if the object is different (by objectID)
            if currentObject != object {
                setObject(object)
                continuation?.yield(UnsafeSendableValue(value: object))
            } else if let currentObject = currentObject, let object {
                // If same objectID but potentially updated values, check if we need to update
                // This is a simple approach - in a real app you might want to compare specific properties
                if currentObject.isUpdated {
                    setObject(object)
                    continuation?.yield(UnsafeSendableValue(value: object))
                }
            }
        } catch {
            print("Error fetching object: \(error)")
            // Don't change the current object on error
        }
    }
    
    // MARK: - Stream Control
    
    func cancelStream() {
        isStreamActive = false
        continuation?.finish()
        continuation = nil
    }
    
    func createNewStream() -> AsyncStream<UnsafeSendableValue<T?>> {
        // Cancel existing stream if active
        if isStreamActive {
            cancelStream()
        }
        
        // Create new stream
        isStreamActive = true
        var newContinuation: AsyncStream<UnsafeSendableValue<T?>>.Continuation!
        let newStream = AsyncStream<UnsafeSendableValue<T?>> { cont in
            newContinuation = cont
            // Send current object immediately
            cont.yield(UnsafeSendableValue(value: currentObject))
        }
        self.continuation = newContinuation
        
        // Store and return the new stream
        _objectStream = newStream
        return newStream
    }
    
    // MARK: - Convenience Methods
    
    func object() -> T? {
        return currentObject
    }
}
