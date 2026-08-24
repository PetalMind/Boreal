//
//  BorealApp.swift
//  Boreal
//
//  Created by Dominik on 24/08/2026.
//

import SwiftUI

@main
struct BorealApp: App {
    @State private var store = BorealStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
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
            }
        }

        Settings {
            TabView {
                Tab("General", systemImage: "gearshape") { GeneralSettingsView() }
                Tab("Runtime", systemImage: "gearshape.2") { RuntimeSettingsView() }
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
