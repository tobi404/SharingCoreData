//
//  GroupedObjectFetcher.swift
//  sharing-core-data
//
//  Created by Beka Demuradze on 24.04.25.
//

@preconcurrency import CoreData

@MainActor
final class GroupedObjectFetcher<T: NSManagedObject, C: NSManagedObject>: Sendable {
    // MARK: - Properties
    
    nonisolated private let groupRequest: NSFetchRequest<T>
    nonisolated private let childRequest: @Sendable (T) -> NSFetchRequest<C>
    nonisolated private let context: NSManagedObjectContext
    private var parentListener: ContextListener<T>?  // NEW: Listener for parent type
    private var childListener: ContextListener<C>?   // RENAMED: Listener for child type
    
    // AsyncStream properties
    private var isStreamActive = true
    private var continuation: AsyncStream<[T: [C]]>.Continuation?
    private var _groupedObjectsStream: AsyncStream<[T: [C]]>?
    var groupedObjectsStream: AsyncStream<[T: [C]]> {
        if let stream = _groupedObjectsStream {
            return stream
        }
        
        // Initialize on first access
        var cont: AsyncStream<[T: [C]]>.Continuation!
        let stream = AsyncStream<[T: [C]]> { continuation in
            cont = continuation
            continuation.yield([:])
        }
        
        // Store the values
        self.continuation = cont
        self._groupedObjectsStream = stream
        return stream
    }
    // Current value cache
    private var currentGroupedObjects: [T: [C]] = [:]
    
    // MARK: - Initialization
    
    nonisolated init(
        groupRequest: NSFetchRequest<T>,
        childRequest: @escaping @Sendable (T) -> NSFetchRequest<C>,
        context: NSManagedObjectContext
    ) {
        self.groupRequest = groupRequest
        self.childRequest = childRequest
        self.context = context
        
        Task { @MainActor in
            _ = self.groupedObjectsStream
            await self.setupListeners()
            await self.fetch()
        }
    }
    
    // MARK: - Setup
    
    private func setupListeners() async {
        // Listen for changes to PARENT objects (e.g., CardCollection)
        let parentContextListener = ContextListener<T>(
            context: context
        ) { [weak self] _ in
            guard let self = self else { return }
            
            Task {
                await self.fetch()
            }
        }
        
        // Listen for changes to CHILD objects (e.g., Card)
        let childContextListener = ContextListener<C>(
            context: context
        ) { [weak self] _ in
            guard let self = self else { return }
            
            Task {
                await self.fetch()
            }
        }
        
        self.parentListener = parentContextListener
        self.childListener = childContextListener
    }
    
    private func setCurrentGroupedObjects(_ newValue: [T: [C]]) {
        currentGroupedObjects = newValue
    }
    
    // MARK: - Fetching
    
    func fetch() async {
        guard isStreamActive else { return }
        
        do {
            var group = [T: [C]]()
            let results = try context.fetch(groupRequest)
            for result in results {
                let childRequst = childRequest(result)
                let childs = try context.fetch(childRequst)
                group[result] = childs
            }
            setCurrentGroupedObjects(group)
            continuation?.yield(group)
        } catch {
            print("Error fetching grouped objects: \(error)")
            continuation?.yield([:])
        }
    }
    
    // MARK: - Stream Control
    
    func cancelStream() {
        isStreamActive = false
        continuation?.finish()
        continuation = nil
    }
    
    func createNewStream() -> AsyncStream<[T: [C]]> {
        // Cancel existing stream if active
        if isStreamActive {
            cancelStream()
        }
        
        // Create new stream
        isStreamActive = true
        var newContinuation: AsyncStream<[T: [C]]>.Continuation!
        let newStream = AsyncStream<[T: [C]]> { cont in
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
    
    func groupedObjects() -> [T: [C]] {
        currentGroupedObjects
    }
}
