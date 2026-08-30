//
//  BorealApp.swift
//  Boreal
//
//  Created by Dominik on 24/08/2026.
//

import AppKit
import SwiftUI

@main
struct BorealApp: App {
    @State private var store = BorealStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.pauseAllStoreGameOperations()
                }
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Install Windows App…") {
                    NotificationCenter.default.post(name: .installWindowsApp, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("View") {
                Button("Grid") { NotificationCenter.default.post(name: .showLibraryGrid, object: nil) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("List") { NotificationCenter.default.post(name: .showLibraryList, object: nil) }
                    .keyboardShortcut("2", modifiers: .command)
                Divider()
                Button("Toggle Game Overlay") { GameOverlayController.shared.toggleVisibility() }
                    .keyboardShortcut("o", modifiers: [.command, .option])
                Button("Cycle Overlay Information Level") { GameOverlayController.shared.cycleDetailLevel() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                Menu("Overlay Information Level") {
                    Button("Minimal") { GameOverlayController.shared.setDetailLevel(.minimal) }
                        .keyboardShortcut("1", modifiers: [.command, .option])
                    Button("Standard") { GameOverlayController.shared.setDetailLevel(.standard) }
                        .keyboardShortcut("2", modifiers: [.command, .option])
                    Button("Diagnostic") { GameOverlayController.shared.setDetailLevel(.diagnostic) }
                        .keyboardShortcut("3", modifiers: [.command, .option])
                }
            }
        }

        Settings {
            TabView {
                Tab("General", systemImage: "gearshape") { GeneralSettingsView() }
                Tab("Runtime", systemImage: "gearshape.2") { RuntimeSettingsView() }
                Tab("Overlay", systemImage: "gauge.with.dots.needle.67percent") { GameOverlaySettingsView() }
                Tab("Advanced", systemImage: "wrench.and.screwdriver") { AdvancedSettingsView() }
            }
        }
    }
}

extension Notification.Name {
    static let installWindowsApp = Notification.Name("Boreal.installWindowsApp")
    static let showLibraryGrid = Notification.Name("Boreal.showLibraryGrid")
    static let showLibraryList = Notification.Name("Boreal.showLibraryList")
}
