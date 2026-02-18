import CoreData
import SharingCoreData
import SwiftUI

struct ContentView: View {
    @SharedReader(
        .fetchAll(
            for: Person.self,
            descriptors: [NSSortDescriptor(key: "updatedAt", ascending: false)]
        )
    )
    private var people: [Person]

    @SharedReader(.fetchCount(for: Person.self))
    private var peopleCount: Int

    @StateObject private var driver: AutoUpdateDriver

    init(container: NSPersistentContainer) {
        _driver = StateObject(wrappedValue: AutoUpdateDriver(container: container))
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                summarySection
                controlsSection
                peopleList
            }
            .padding()
            .navigationBarTitle("Automatic Updates")
        }
        .onAppear {
            driver.start()
        }
        .onDisappear {
            driver.stop()
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("People count: \(peopleCount)")
                .font(.headline)
            Text("Latest tick: \(latestTickDescription)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Driver: \(driver.isRunning ? "Running" : "Stopped")")
                .font(.subheadline)
                .foregroundColor(driver.isRunning ? .green : .red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controlsSection: some View {
        HStack(spacing: 12) {
            Button("Start") {
                driver.start()
            }
            .disabled(driver.isRunning)

            Button("Stop") {
                driver.stop()
            }
            .disabled(!driver.isRunning)

            Button("Reset") {
                Task {
                    await driver.reset()
                }
            }
        }
    }

    private var peopleList: some View {
        List(people, id: \.objectID) { person in
            VStack(alignment: .leading, spacing: 4) {
                Text(person.name)
                    .font(.headline)
                Text("Tick \(person.tick)")
                    .font(.subheadline)
                Text(Self.dateFormatter.string(from: person.updatedAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .listStyle(.plain)
    }

    private var latestTickDescription: String {
        guard let latest = people.first else { return "No updates yet" }
        return "#\(latest.tick) at \(Self.timeFormatter.string(from: latest.updatedAt))"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}
