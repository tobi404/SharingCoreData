//
//  GroupedObjectFetcher.swift
//  sharing-core-data
//
//  Created by Beka Demuradze on 24.04.25.
//

@preconcurrency import CoreData

actor GroupedObjectFetcher<T: NSManagedObject, KeyType: Sendable & Hashable>: Sendable {
    // MARK: - Properties
    
    private let fetchRequest: NSFetchRequest<T>
    private let context: NSManagedObjectContext
    private let keyPath: KeyPath<T, KeyType?>
    private var listener: ContextListener<T>?
    
    // AsyncStream properties
    private var isStreamActive = true
    private var continuation: AsyncStream<[KeyType: [T]]>.Continuation?
    private var _groupedObjectsStream: AsyncStream<[KeyType: [T]]>?
    var groupedObjectsStream: AsyncStream<[KeyType: [T]]> {
        if let stream = _groupedObjectsStream {
            return stream
        }
        
        // Initialize on first access
        var cont: AsyncStream<[KeyType: [T]]>.Continuation!
        let stream = AsyncStream<[KeyType: [T]]> { continuation in
            cont = continuation
            continuation.yield([:])
        }
        
        // Store the values
        self.continuation = cont
        self._groupedObjectsStream = stream
        return stream
    }
    // Current value cache
    private var currentGroupedObjects: [KeyType: [T]] = [:]
    
    // MARK: - Initialization
    
    init(
        fetchRequest: NSFetchRequest<T>,
        context: NSManagedObjectContext,
        keyPath: KeyPath<T, KeyType?>
    ) {
        self.fetchRequest = fetchRequest
        self.context = context
        self.keyPath = keyPath
        
        Task {
            _ = await groupedObjectsStream
            await setupListener()
            await fetch()
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
    
    private func setCurrentGroupedObjects(_ newValue: [KeyType: [T]]) {
        currentGroupedObjects = newValue
    }
    
    // MARK: - Fetching
    
    @MainActor
    func fetch() async {
        guard await isStreamActive else { return }
        
        do {
            let results = try await context.fetch(fetchRequest)
            let grouped = await groupTheObjects(results: results)
            await setCurrentGroupedObjects(grouped)
            await continuation?.yield(grouped)
        } catch {
            print("Error fetching grouped objects: \(error)")
            await continuation?.yield([:])
        }
    }
    
    // MARK: - Stream Control
    
    func cancelStream() {
        isStreamActive = false
        continuation?.finish()
        continuation = nil
    }
    
    func createNewStream() -> AsyncStream<[KeyType: [T]]> {
        // Cancel existing stream if active
        if isStreamActive {
            cancelStream()
        }
        
        // Create new stream
        isStreamActive = true
        var newContinuation: AsyncStream<[KeyType: [T]]>.Continuation!
        let newStream = AsyncStream<[KeyType: [T]]> { cont in
            newContinuation = cont
            // Send current objects immediately
            cont.yield(currentGroupedObjects)
        }
        self.continuation = newContinuation
        
        // Store and return the new stream
        _groupedObjectsStream = newStream
        return newStream
    }
    
    // MARK: - Convenience Methods
    
    func groupedObjects() -> [KeyType: [T]] {
        currentGroupedObjects
    }
    
    func groupTheObjects(results: [T]) -> [KeyType: [T]] {
        var dict = [KeyType: [T]]()
        for object in results {
            guard let key = object[keyPath: keyPath] else { continue }
            dict[key, default: []].append(object)
        }
        return dict
    }
}
