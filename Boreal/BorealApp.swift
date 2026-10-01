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
    @State private var store: BorealStore
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue

    init() {
        do {
            if UserDefaults.standard.string(forKey: ApplicationDataLocation.pendingPathKey) != nil,
               let bundleID = Bundle.main.bundleIdentifier,
               NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: {
                   $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
               }) {
                throw ApplicationDataLocation.LocationError(message: "Close other Boreal windows before moving application data.")
            }
            try ApplicationDataLocation.prepare()
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "Boreal data location is unavailable")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: String(localized: "Quit"))
            if UserDefaults.standard.string(forKey: ApplicationDataLocation.pendingPathKey) != nil {
                alert.addButton(withTitle: String(localized: "Cancel Location Change"))
            }
            if alert.runModal() == .alertSecondButtonReturn {
                ApplicationDataLocation.cancel()
                do { try ApplicationDataLocation.prepare() }
                catch {
                    alert.informativeText = error.localizedDescription
                    _ = alert.runModal()
                    exit(EXIT_FAILURE)
                }
            } else {
                exit(EXIT_FAILURE)
            }
        }
        _store = State(initialValue: BorealStore())
    }

    private var selectedLocale: Locale {
        let language = AppLanguage(rawValue: appLanguage) ?? .system
        return language.locale ?? .current
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(\.locale, selectedLocale)
                .task {
                    DiscordPresence.shared.start()
                    ControllerManager.shared.start()
                    await store.runAutomaticCompatibilityUpdateCheck()
                    await store.runAutomaticGameDiscovery()
                    await store.runAutomaticLibraryRefreshLoop()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    DiscordPresence.shared.shutdown()
                    ControllerManager.shared.shutdown()
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
            BorealSettingsView()
                .environment(store)
                .environment(\.locale, selectedLocale)
        }
    }
}

extension Notification.Name {
    static let installWindowsApp = Notification.Name("Boreal.installWindowsApp")
    static let showLibraryGrid = Notification.Name("Boreal.showLibraryGrid")
    static let showLibraryList = Notification.Name("Boreal.showLibraryList")
    static let borealControllerConnected = Notification.Name("Boreal.controllerConnected")
    static let borealControllerInputPressed = Notification.Name("Boreal.controllerInputPressed")
    static let borealControllerQuickMenu = Notification.Name("Boreal.controllerQuickMenu")
    static let borealOpenRuntimeSettings = Notification.Name("Boreal.openRuntimeSettings")
    static let borealRuntimeImportCompleted = Notification.Name("Boreal.runtimeImportCompleted")
}
