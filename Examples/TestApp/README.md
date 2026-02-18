# TestApp Example (Source-Only)

This folder contains a minimal SwiftUI example that demonstrates automatic UI updates with `SharingCoreData`.

## What it shows

- A persisted SQLite Core Data store (`Application Support/SharingCoreDataTestApp/TestApp.sqlite`)
- Background writes every 2 seconds from `AutoUpdateDriver`
- Automatic UI refresh via:
  - `@SharedReader(.fetchAll(for: Person.self, ...))`
  - `@SharedReader(.fetchCount(for: Person.self))`
- Manual controls to `Start`, `Stop`, and `Reset` data

## Files

- `App.swift`: app entry point + dependency setup (`prepareDependencies`)
- `ContentView.swift`: UI and `@SharedReader`-backed reads
- `AutoUpdateDriver.swift`: timer loop and background Core Data mutations
- `Persistence/CoreDataStack.swift`: programmatic Core Data model + SQLite container setup
- `Persistence/Person.swift`: `NSManagedObject` subclass for demo data

## How to run

This repo ships the example as source files only.

1. Create an iOS SwiftUI app target.
2. Add this package and link `SharingCoreData`.
3. Copy these files into your app target.
4. Build and run. The list and count should update automatically every few seconds.
