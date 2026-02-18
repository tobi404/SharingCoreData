import Testing
import Dependencies
@preconcurrency import CoreData
@testable import SharingCoreData

@Test
func fetchAllIDIncludesBatchAndPrefetchConfiguration() async throws {
    let container = try await makeInMemoryContainer()
    let (lhs, rhs) = withDependencies {
        $0.persistentContainer = container
    } operation: {
        let predicate = NSPredicate(format: "name == %@", "alex")

        let lhs = FetchAllObjectKey(
            for: TestItemMO.self,
            predicate: predicate,
            sort: [],
            relationshipKeyPathsForPrefetching: [],
            batchSize: nil
        ).id

        let rhs = FetchAllObjectKey(
            for: TestItemMO.self,
            predicate: predicate,
            sort: [],
            relationshipKeyPathsForPrefetching: ["children"],
            batchSize: 50
        ).id

        return (lhs, rhs)
    }

    #expect(lhs != rhs)
}

@Test
func queryKindsDoNotCollideForSameFetchRequestShape() async throws {
    let container = try await makeInMemoryContainer()
    let (allID, countID) = withDependencies {
        $0.persistentContainer = container
    } operation: {
        let predicate = NSPredicate(format: "name == %@", "alex")

        let allID = FetchAllObjectKey(
            for: TestItemMO.self,
            predicate: predicate,
            sort: [],
            relationshipKeyPathsForPrefetching: [],
            batchSize: nil
        ).id
        let countID = FetchCountKey(
            for: TestItemMO.self,
            predicate: predicate
        ).id
        return (allID, countID)
    }

    #expect(allID != countID)
}

@Test
func groupedIDsIncludeChildRequestIdentity() async throws {
    let container = try await makeInMemoryContainer()
    let (lhs, rhs) = withDependencies {
        $0.persistentContainer = container
    } operation: {
        let parentRequest = TestParentMO.fetchRequest()

        let lhs = FetchGroupedObjectKey<TestParentMO, TestChildMO>(
            group: parentRequest,
            child: { _ in
                let request = TestChildMO.fetchRequest()
                request.predicate = NSPredicate(format: "name BEGINSWITH %@", "a")
                return request
            },
            groupingIdentity: "child-request-a"
        ).id

        let rhs = FetchGroupedObjectKey<TestParentMO, TestChildMO>(
            group: parentRequest,
            child: { _ in
                let request = TestChildMO.fetchRequest()
                request.predicate = NSPredicate(format: "name BEGINSWITH %@", "b")
                return request
            },
            groupingIdentity: "child-request-b"
        ).id

        return (lhs, rhs)
    }

    #expect(lhs != rhs)
}

@MainActor
@Test
func unrelatedDeleteDoesNotClearTrackedSingleObject() async throws {
    let container = try await makeInMemoryContainer()
    let context = container.viewContext

    let tracked = TestItemMO(context: context)
    tracked.id = UUID()
    tracked.name = "tracked"

    let unrelated = TestItemMO(context: context)
    unrelated.id = UUID()
    unrelated.name = "unrelated"
    try context.save()

    let request = TestItemMO.fetchRequest()
    request.predicate = NSPredicate(format: "id == %@", tracked.id as NSUUID)

    let fetcher = SingleObjectFetcher(fetchRequest: request, context: context)
    let didLoadTracked = await waitUntil(timeoutNanoseconds: 1_000_000_000) {
        fetcher.object()?.objectID == tracked.objectID
    }
    #expect(didLoadTracked)

    context.delete(unrelated)
    try context.save()

    try await Task.sleep(nanoseconds: 300_000_000)
    #expect(fetcher.object()?.objectID == tracked.objectID)

    fetcher.cancelStream()
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64,
    stepNanoseconds: UInt64 = 20_000_000,
    condition: @MainActor () -> Bool
) async -> Bool {
    let iterations = max(1, Int(timeoutNanoseconds / stepNanoseconds))
    for _ in 0..<iterations {
        if condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: stepNanoseconds)
    }
    return condition()
}

private func makeInMemoryContainer() async throws -> NSPersistentContainer {
    let container = NSPersistentContainer(name: "SharingCoreDataTests", managedObjectModel: sharedTestModel)
    let description = NSPersistentStoreDescription()
    description.type = NSInMemoryStoreType
    description.shouldAddStoreAsynchronously = false
    container.persistentStoreDescriptions = [description]

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        container.loadPersistentStores { _, error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: ())
            }
        }
    }
    return container
}

private let sharedTestModel: NSManagedObjectModel = {
    let model = NSManagedObjectModel()
    model.entities = [
        testItemEntityDescription(),
        testParentEntityDescription(),
        testChildEntityDescription(),
    ]
    return model
}()

private func testItemEntityDescription() -> NSEntityDescription {
    let entity = NSEntityDescription()
    entity.name = "TestItemMO"
    entity.managedObjectClassName = NSStringFromClass(TestItemMO.self)
    entity.properties = [
        attribute(name: "id", type: .UUIDAttributeType),
        attribute(name: "name", type: .stringAttributeType),
    ]
    return entity
}

private func testParentEntityDescription() -> NSEntityDescription {
    let entity = NSEntityDescription()
    entity.name = "TestParentMO"
    entity.managedObjectClassName = NSStringFromClass(TestParentMO.self)
    entity.properties = [
        attribute(name: "id", type: .UUIDAttributeType),
        attribute(name: "name", type: .stringAttributeType),
    ]
    return entity
}

private func testChildEntityDescription() -> NSEntityDescription {
    let entity = NSEntityDescription()
    entity.name = "TestChildMO"
    entity.managedObjectClassName = NSStringFromClass(TestChildMO.self)
    entity.properties = [
        attribute(name: "id", type: .UUIDAttributeType),
        attribute(name: "name", type: .stringAttributeType),
    ]
    return entity
}

private func attribute(name: String, type: NSAttributeType) -> NSAttributeDescription {
    let attribute = NSAttributeDescription()
    attribute.name = name
    attribute.attributeType = type
    attribute.isOptional = false
    return attribute
}

@objc(TestItemMO)
final class TestItemMO: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String

    @nonobjc
    class func fetchRequest() -> NSFetchRequest<TestItemMO> {
        NSFetchRequest(entityName: "TestItemMO")
    }
}

extension TestItemMO: Identifiable {}

@objc(TestParentMO)
final class TestParentMO: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String

    @nonobjc
    class func fetchRequest() -> NSFetchRequest<TestParentMO> {
        NSFetchRequest(entityName: "TestParentMO")
    }
}

@objc(TestChildMO)
final class TestChildMO: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String

    @nonobjc
    class func fetchRequest() -> NSFetchRequest<TestChildMO> {
        NSFetchRequest(entityName: "TestChildMO")
    }
}
