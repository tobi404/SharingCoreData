//
//  SingleObjectFetcher.swift
//  sharing-core-data
//
//  Created by Beka Demuradze on 24.04.25.
//

@preconcurrency import CoreData

actor SingleObjectFetcher<T: NSManagedObject & Identifiable>: Sendable {
    // MARK: - Properties
    
    private let fetchRequest: NSFetchRequest<T>
    private let context: NSManagedObjectContext
    private var listener: ContextListener<T>?
    
    // AsyncStream properties
    private var continuation: AsyncStream<T?>.Continuation?
    private var isStreamActive = true
    private var _objectStream: AsyncStream<T?>?
    var objectStream: AsyncStream<T?> {
        if let _objectStream {
            return _objectStream
        }
        
        var continuation: AsyncStream<T?>.Continuation!
        let stream = AsyncStream<T?> { cont in
            continuation = cont
            // Send initial nil
            cont.yield(nil)
        }
        
        self._objectStream = stream
        self.continuation = continuation
        return stream
    }
    
    // Current value cache
    private var currentObject: T?
    
    // MARK: - Initialization
    
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
            _ = await objectStream
            await setupListener()
            await fetch()
        }
    }
    
    // MARK: - Setup
    
    private func setupListener() async {
        let contextListener = ContextListener<T>(
            context: context
        ) { [weak self] changeType in
            guard let self = self else { return }
            
            Task {
                switch changeType {
                case .inserted, .updated:
                    // Refetch the object on insert or update
                    await self.fetch()
                case .deleted:
                    // If our object was deleted, set to nil
                    if await self.currentObject != nil {
                        await setToNil()
                    }
                }
            }
        }
        
        self.listener = contextListener
    }
    
    private func setToNil() {
        self.currentObject = nil
        self.continuation?.yield(nil)
    }
    
    private func setObject(_ newValue: T?) {
        currentObject = newValue
    }
    
    // MARK: - Fetching
    
    @MainActor
    func fetch() async {
        guard await isStreamActive else { return }
        
        do {
            let results = try await context.fetch(fetchRequest)
            let object = results.first
            
            // Only yield if the object is different (by objectID)
            if await currentObject != object {
                await setObject(object)
                await continuation?.yield(object)
            } else if let currentObject = await currentObject, let object {
                // If same objectID but potentially updated values, check if we need to update
                // This is a simple approach - in a real app you might want to compare specific properties
                if currentObject.isUpdated {
                    await setObject(object)
                    await continuation?.yield(object)
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
    
    func createNewStream() -> AsyncStream<T?> {
        // Cancel existing stream if active
        if isStreamActive {
            cancelStream()
        }
        
        // Create new stream
        isStreamActive = true
        var newContinuation: AsyncStream<T?>.Continuation!
        let newStream = AsyncStream<T?> { cont in
            newContinuation = cont
            // Send current object immediately
            cont.yield(currentObject)
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
