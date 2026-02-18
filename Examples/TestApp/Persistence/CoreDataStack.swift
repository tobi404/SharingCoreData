import CoreData
import Foundation

enum ExampleCoreDataStack {
    private static let modelName = "TestAppModel"
    private static let sqliteFileName = "TestApp.sqlite"

    static func makePersistentContainer() -> NSPersistentContainer {
        let container = NSPersistentContainer(
            name: modelName,
            managedObjectModel: managedObjectModel()
        )

        let description = NSPersistentStoreDescription(url: persistentStoreURL())
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Failed to load persistent store: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy

        return container
    }

    private static func managedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.entities = [personEntity()]
        return model
    }

    private static func personEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "Person"
        entity.managedObjectClassName = NSStringFromClass(Person.self)
        entity.properties = [
            attribute(name: "id", type: .UUIDAttributeType),
            attribute(name: "name", type: .stringAttributeType),
            attribute(name: "updatedAt", type: .dateAttributeType),
            attribute(name: "tick", type: .integer64AttributeType),
        ]
        entity.uniquenessConstraints = [["id"]]
        return entity
    }

    private static func attribute(name: String, type: NSAttributeType) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = false
        return attribute
    }

    private static func persistentStoreURL() -> URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directoryURL = appSupportURL.appendingPathComponent("SharingCoreDataTestApp", isDirectory: true)

        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        return directoryURL.appendingPathComponent(sqliteFileName)
    }
}
