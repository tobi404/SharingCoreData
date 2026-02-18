# SharingCoreData

`SharingCoreData` integrates Core Data with [swift-sharing](https://github.com/pointfreeco/swift-sharing) so Core Data fetches can back `@SharedReader` state.

## Requirements

- Swift 6.0+
- iOS 13+, macOS 11+, tvOS 13+, watchOS 7+

## Installation

Add this package to your `Package.swift` dependencies:

```swift
.package(url: "https://github.com/bekademuradze/sharing-core-data.git", from: "1.0.0")
```

Then add the product:

```swift
.product(name: "SharingCoreData", package: "sharing-core-data")
```

## Choosing the Right Tool

If you are starting a new iOS project, I recommend
[`sqlite-data`](https://github.com/pointfreeco/sqlite-data). In my opinion,
it is the better default for greenfield development.

If you are working in an existing project that already uses Core Data and want
to bring in the sharing library, feel free to try this package.

## Quick Start

Configure your app's `NSPersistentContainer` as early as possible:

```swift
import SharingCoreData
import Dependencies
import CoreData

prepareDependencies {
  $0.persistentContainer = NSPersistentContainer(name: "Model")
}
```

Read Core Data state via shared reader keys:

```swift
@SharedReader(.fetchAll(for: Item.self))
var items: [Item]

@SharedReader(.fetch(for: Item.self, predicate: NSPredicate(format: "id == %@", id as NSUUID)))
var item: Item?

@SharedReader(.fetchCount(for: Item.self))
var itemCount: Int
```

Grouped fetches:

```swift
@SharedReader(
  .fetchGrouped(
    groupRequest: Collection.fetchRequest(),
    childRequest: { collection in
      let request = Item.fetchRequest()
      request.predicate = NSPredicate(format: "collection == %@", collection)
      return request
    }
  )
)
var groupedItems: [Collection: [Item]]
```

## Core Data + Concurrency Contract

- API values are `NSManagedObject`-backed and intended for `@MainActor` consumption.
- Never pass `NSManagedObject` instances across contexts/tasks.
- Use `NSManagedObjectID` for cross-context communication.
- Internal async transport uses local wrappers, not global Core Data retroactive sendability conformances.
