//
//  ObjectCountFetcher.swift
//  sharing-core-data
//
//  Created by Beka Demuradze on 24.04.25.
//

@preconcurrency import CoreData

@MainActor
final class ObjectCountFetcher<T: NSManagedObject>: Sendable {
    
    // MARK: - Properties
    
    private let fetchRequest: NSFetchRequest<T>
    private let context: NSManagedObjectContext
    private var listener: ContextListener<T>?
    
    // AsyncStream properties
    private var continuation: AsyncStream<Int>.Continuation?
    private var isStreamActive = true
    private var _countStream: AsyncStream<Int>?
    var countStream: AsyncStream<Int> {
        if let stream = _countStream {
            return stream
        }
        
        var continuation: AsyncStream<Int>.Continuation!
        let stream = AsyncStream<Int> { cont in
            continuation = cont
            // Send initial zero count
            cont.yield(0)
        }
        self._countStream = stream
        self.continuation = continuation
        return stream
    }
    
    // Current value cache
    private var currentCount: Int = 0
    
    // MARK: - Initialization
    
    @MainActor
    init(
        fetchRequest: NSFetchRequest<T>,
        context: NSManagedObjectContext
    ) {
        self.fetchRequest = fetchRequest
        self.context = context
        
        Task {
            _ = self.countStream
            await self.setupListener()
            await self.fetchCount()
        }
    }
    
    // MARK: - Setup
    
    private func setupListener() async {
        let contextListener = ContextListener<T>(
            context: context
        ) { [weak self] _ in
            guard let self = self else { return }
            
            Task {
                await self.fetchCount()
            }
        }
        
        self.listener = contextListener
    }
    
    private func setCount(_ newValue: Int) {
        currentCount = newValue
    }
    
    // MARK: - Fetching
    
    func fetchCount() async {
        guard isStreamActive else { return }
        
        do {
            // Create a copy of the fetch request to avoid modifying the original
            let countRequest = fetchRequest.copy() as! NSFetchRequest<T>
            
            // Set result type to count only for efficiency
            countRequest.resultType = .countResultType
            
            // Execute the count request
            let countResult = try context.count(for: countRequest)
            setCount(countResult)
            continuation?.yield(countResult)
        } catch {
            print("Error fetching count: \(error)")
            continuation?.yield(0)
        }
    }
    
    // MARK: - Stream Control
    
    func cancelStream() {
        isStreamActive = false
        continuation?.finish()
        continuation = nil
    }
    
    func createNewStream() -> AsyncStream<Int> {
        // Cancel existing stream if active
        if isStreamActive {
            cancelStream()
        }
        
        // Create new stream
        isStreamActive = true
        var newContinuation: AsyncStream<Int>.Continuation!
        let newStream = AsyncStream<Int> { cont in
            newContinuation = cont
            // Send current count immediately
            cont.yield(currentCount)
        }
        self.continuation = newContinuation
        
        // Store and return the new stream
        _countStream = newStream
        return newStream
    }
    
    // MARK: - Convenience Methods
    
    func count() -> Int {
        currentCount
    }
}
