//  TestApp.swift
//  Test

import SwiftUI
import SwiftData   // ⬅️ add this

@main
struct TestApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // ⬇️ attach the shared SwiftData container for your models
        .modelContainer(for: [Project.self, WorkSession.self])
        // if/when you add Expense later: .modelContainer(for: [Project.self, WorkSession.self, Expense.self])
    }
}
