import CoreData
import Foundation

@MainActor
final class AutoUpdateDriver: ObservableObject {
    @Published private(set) var isRunning = false

    private let container: NSPersistentContainer
    private var loopTask: Task<Void, Never>?
    private let seedCount = 5

    init(container: NSPersistentContainer) {
        self.container = container
    }

    deinit {
        loopTask?.cancel()
    }

    func start() {
        guard loopTask == nil else { return }

        isRunning = true
        loopTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await self.performTick()
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    break
                }
            }

            await MainActor.run {
                self.loopTask = nil
                self.isRunning = false
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        isRunning = false
    }

    func reset() async {
        await writeInBackground { context in
            let request = Person.fetchRequest()
            request.includesPropertyValues = false
            let people = try context.fetch(request)
            for person in people {
                context.delete(person)
            }
        }
    }

    private func performTick() async {
        let seedCount = self.seedCount
        await writeInBackground { context in
            let now = Date()
            let nextTick = try Self.nextTickValue(in: context)
            let count = try context.count(for: Person.fetchRequest())

            if count < seedCount {
                let person = Person(context: context)
                person.id = UUID()
                person.name = "Person \(nextTick)"
                person.updatedAt = now
                person.tick = nextTick
                return
            }

            let request = Person.fetchRequest()
            request.fetchLimit = 1
            request.fetchOffset = Int.random(in: 0..<count)

            if let person = try context.fetch(request).first {
                person.name = "Person \(nextTick)"
                person.updatedAt = now
                person.tick = nextTick
            }
        }
    }

    private func writeInBackground(
        _ mutation: @escaping (NSManagedObjectContext) throws -> Void
    ) async {
        let container = self.container
        await withCheckedContinuation { continuation in
            let context = container.newBackgroundContext()
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

            context.perform {
                do {
                    try mutation(context)
                    if context.hasChanges {
                        try context.save()
                    }
                } catch {
                    print("AutoUpdateDriver write failed: \(error)")
                }

                continuation.resume()
            }
        }
    }

    private nonisolated static func nextTickValue(in context: NSManagedObjectContext) throws -> Int64 {
        let request = Person.fetchRequest()
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "tick", ascending: false)]

        let currentTick = try context.fetch(request).first?.tick ?? 0
        return currentTick + 1
    }
}
