import SwiftUI
import SharingCoreData

@main
struct TestApp: App {
    private let persistentContainer = ExampleCoreDataStack.makePersistentContainer()

    init() {
        prepareDependencies {
            $0.persistentContainer = persistentContainer
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(container: persistentContainer)
        }
    }
}
