//  TestApp.swift
//  Test

import SwiftUI
import SwiftData

@main
struct TestApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(BootstrapSync()) // one-time CloudKit pull on launch
        }
        .modelContainer(for: [Project.self, WorkSession.self])
    }
}

/// A lightweight helper view that runs after the SwiftData ModelContext exists.
/// It performs an initial CloudKit pull to rehydrate local data on fresh installs.
private struct BootstrapSync: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        Color.clear
            .task {
                CloudKitSyncEngine.shared.prepareForFirstRun()
                // If you haven't added CloudKitSyncEngine yet, comment this out for now.
                await CloudKitSyncEngine.shared.pullAll(context: context)
            }
    }
}
