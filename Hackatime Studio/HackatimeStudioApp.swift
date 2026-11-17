//
//  HackatimeStudioApp.swift
//  Hackatime Studio
//
//  Created by Harshil on 2026-11-17.
//

import SwiftUI

@main
struct HackatimeStudioApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Hackatime Studio") {
            ContentView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 640)
                .task {
                    #if DEBUG
                    DebugSnapshots.runIfRequested(model: model)
                    #endif
                    await model.bootstrap()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.appBecameActive()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.route = .settings }.keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu("Studio") {
                Button("Refresh") { Task { await model.refreshAll() } }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Dashboard") { model.route = .dashboard }.keyboardShortcut("1", modifiers: .command)
                Button("Configuration") { model.route = .configuration }.keyboardShortcut("2", modifiers: .command)
                Button("Folders & Projects") { model.route = .folders }.keyboardShortcut("3", modifiers: .command)
                Button("Editors") { model.route = .editors }.keyboardShortcut("4", modifiers: .command)
                Button("Diagnostics") { model.route = .diagnostics }.keyboardShortcut("5", modifiers: .command)
                Divider()
                Button("Reveal Config File in Finder") { model.perform(.reveal(model.location.url)) }
            }
        }
    }
}
