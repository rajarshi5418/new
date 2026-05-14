// CameraClaudeApp.swift
// Main entry point for the CameraClaude iOS app.
// Uses SwiftData for persistent storage of DocumentRecord models.

import SwiftUI
import SwiftData

@main
struct CameraClaudeApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([DocumentRecord.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
