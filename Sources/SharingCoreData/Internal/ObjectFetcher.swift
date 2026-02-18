//
//  ObjectFetcher.swift
//  sharing-core-data
//
//  Created by Beka Demuradze on 24.04.25.
//

@preconcurrency import CoreData

@MainActor
final class ObjectFetcher<T: NSManagedObject>: Sendable {
    
    // MARK: - Properties
    var objectsStream: AsyncStream<UnsafeSendableValue<[T]>> {
        if let _objectsStream {
            return _objectsStream
        }
        
        var continuation: AsyncStream<UnsafeSendableValue<[T]>>.Continuation!
        let stream = AsyncStream<UnsafeSendableValue<[T]>> { cont in
            continuation = cont
            // Send initial empty array
            cont.yield(UnsafeSendableValue(value: []))
        }
        self._objectsStream = stream
        self.continuation = continuation
        return stream
    }
    
    private let fetchRequest: NSFetchRequest<T>
    private let context: NSManagedObjectContext
    private var listener: ContextListener<T>?
    
    // AsyncStream properties
    private var continuation: AsyncStream<UnsafeSendableValue<[T]>>.Continuation?
    private var isStreamActive = true
    private var _objectsStream: AsyncStream<UnsafeSendableValue<[T]>>?
    
    // Current value cache
    private var currentObjects: [T] = []
    
    // MARK: - Initialization
    
    @MainActor
    init(
        fetchRequest: NSFetchRequest<T>,
        context: NSManagedObjectContext
    ) {
        self.fetchRequest = fetchRequest
        self.context = context
        
        Task {
            _ = self.objectsStream
            await self.setupListener()
            await self.fetch()
        }
    }
    
    // MARK: - Setup
    
    private func setupListener() async {
        let contextListener = ContextListener<T>(
            context: context
        ) { [weak self] _ in
            guard let self = self else { return }
            
            Task {
                await self.fetch()
            }
        }
        
        self.listener = contextListener
    }
    
    private func setCurrentObjects(_ newValue: [T]) {
        currentObjects = newValue
    }
    
    // MARK: - Fetching
    
    func fetch() async {
        guard isStreamActive else { return }
        
        do {
            let results = try context.fetch(fetchRequest)
            setCurrentObjects(results)
            continuation?.yield(UnsafeSendableValue(value: results))
        } catch {
            print("Error fetching objects: \(error)")
            continuation?.yield(UnsafeSendableValue(value: []))
        }
    }
    
    // MARK: - Stream Control
    
    func cancelStream() {
        isStreamActive = false
        continuation?.finish()
        continuation = nil
    }
    
    func createNewStream() -> AsyncStream<UnsafeSendableValue<[T]>> {
        // Cancel existing stream if active
        if isStreamActive {
            cancelStream()
        }
        
        // Create new stream
        isStreamActive = true
        var newContinuation: AsyncStream<UnsafeSendableValue<[T]>>.Continuation!
        let newStream = AsyncStream<UnsafeSendableValue<[T]>> { cont in
            newContinuation = cont
            // Send current objects immediately
            cont.yield(UnsafeSendableValue(value: currentObjects))
        }
        self.continuation = newContinuation
        
        // Store and return the new stream
        _objectsStream = newStream
        return newStream
    }
    
    // MARK: - Convenience Methods
    
    func objects() -> [T] {
        return currentObjects
    }
    
    func refresh(results: [NSManagedObject]) {
        results.forEach { context.refresh($0, mergeChanges: true) }
    }
}
