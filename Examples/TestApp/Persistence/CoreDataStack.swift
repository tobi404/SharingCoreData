//
//  File.swift
//  sharing-CoreData
//
//  Created by Beka Demuradze on 10.04.25.
//

import Foundation
import CoreData

extension NSPersistentContainer {
    static var testing: NSPersistentContainer {
        // Create the NSManagedObjectModel programmatically
        let model = NSManagedObjectModel()
        
        // Define an entity, for example "Person"
        let personEntity = NSEntityDescription()
        personEntity.name = "Person"
        // Adjust the managed object class name according to your project setup.
        personEntity.managedObjectClassName = "Person" // or "YourModuleName.Person"
        
        // Define a non-optional string attribute "name"
        let nameAttribute = NSAttributeDescription()
        nameAttribute.name = "name"
        nameAttribute.attributeType = .stringAttributeType
        nameAttribute.isOptional = false
        
        // Define a non-optional integer attribute "age"
        let ageAttribute = NSAttributeDescription()
        ageAttribute.name = "age"
        ageAttribute.attributeType = .integer16AttributeType
        ageAttribute.isOptional = false
        
        // Add attributes to the entity
        personEntity.properties = [nameAttribute, ageAttribute]
        
        // Set the entity to the model
        model.entities = [personEntity]
        
        // Initialize the persistent container with the in-code model.
        // The name provided here ("MyModel") is arbitrary since you're not using a model file.
        let persistentContainer = NSPersistentContainer(name: "TestDatabase", managedObjectModel: model)
        
        // Load persistent stores as usual.
        persistentContainer.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        
        return persistentContainer
    }
}

@objc(Person)
public class Person: NSManagedObject {
    // Optionally add properties, methods, etc.
}

extension Person {
    @NSManaged public var name: String
    @NSManaged public var age: Int16
}
