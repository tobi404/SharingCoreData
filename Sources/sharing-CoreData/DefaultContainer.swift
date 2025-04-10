//
//  DefaultContainer.swift
//  sharing-CoreData
//
//  Created by Beka Demuradze on 10.04.25.
//

import Dependencies
@preconcurrency import CoreData

extension DependencyValues {
    public var defaultContainer: NSPersistentContainer {
        get { self[DefaultContainerKey.self] }
        set { self[DefaultContainerKey.self] = newValue }
    }
    
    private enum DefaultContainerKey: DependencyKey {
        static var liveValue: NSPersistentContainer { testValue }
        static var testValue: NSPersistentContainer {
            var message: String {
                @Dependency(\.context) var context
                if context == .preview {
                    return """
                    A blank, in-memory database is being used. To set the database that is used by \
                    'SharingGRDB', use the 'prepareDependencies' tool as early as possible in the lifetime \
                    of your preview:
                    
                    #Preview {
                        let _ = prepareDependencies {
                            $0.defaultDatabase = try! DatabaseQueue(/* ... */)
                        }
                    
                        // ...
                    }
                    """
                } else {
                    return """
                    A blank, in-memory database is being used. To set the database that is used by \
                    'SharingGRDB', use the 'prepareDependencies' tool as early as possible in the lifetime \
                    of your app, such as in your app or scene delegate in UIKit, or the app entry point in \
                    SwiftUI:
                    
                    @main
                    struct MyApp: App {
                        init() {
                            prepareDependencies {
                                $0.defaultDatabase = try! DatabaseQueue(/* ... */)
                            }   
                        }
                        
                        // ...
                    }
                    """
                }
            }
            
            reportIssue(message)
            
            let container = NSPersistentContainer(name: .defaultContainerName)
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
            container.loadPersistentStores { description, error in
                if let error {
                    reportIssue(error)
                }
            }
            return container
        }
    }
}

#if DEBUG
extension String {
    static let defaultContainerName = "sharing.core_data.testValue"
}
#endif
