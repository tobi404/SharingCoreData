import CoreData
import Foundation

@objc(Person)
public final class Person: NSManagedObject {
    @nonobjc
    public class func fetchRequest() -> NSFetchRequest<Person> {
        NSFetchRequest<Person>(entityName: "Person")
    }

    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var updatedAt: Date
    @NSManaged public var tick: Int64
}
