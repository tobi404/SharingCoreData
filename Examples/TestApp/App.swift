//
//  App.swift
//  sharing-CoreData
//
//  Created by Beka Demuradze on 10.04.25.
//

import SwiftUI

@main
struct App: View {
    init() {
        prepareDependencies {
            $0.persistentContainer = .testing
        }
    }
    
    var body: some View {
        WindowGroup {
            Text("Hello, World!")
        }
    }
}

#Preview {
    App()
}
