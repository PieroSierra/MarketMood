//
//  MarketMoodApp.swift
//  MarketMood
//
//  Created by Piero Sierra on 06/10/2025.
//

/// TODOS
/// [ ] make pulldown & refresh work on the homepage
/// [ ] make refresh work from widget
/// [X] fix "MSFT" lookup issue
/// [ ] enhance colors a bit
/// [X] fix margin


import SwiftUI
import SwiftData

@main
struct MarketMoodApp: App {
    @StateObject private var appState = AppState()
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .modelContainer(sharedModelContainer)
    }
}
