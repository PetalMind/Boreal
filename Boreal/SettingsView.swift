import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BorealSettingsView: View {
    @State private var selection: SettingsCategory? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selection) { category in
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.title)
                        Text(category.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: category.symbol)
                        .symbolRenderingMode(.hierarchical)
                }
                .tag(category)
                .padding(.vertical, 4)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
            .safeAreaInset(edge: .bottom) {
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—") (Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(16)
            }
        } detail: {
            settingsContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(Text((selection ?? .general).title))
        }
        .frame(minWidth: 760, idealWidth: 1040, minHeight: 560, idealHeight: 720)
        .onReceive(NotificationCenter.default.publisher(for: .borealOpenRuntimeSettings)) { _ in
            selection = .runtime
        }
    }

    @ViewBuilder private var settingsContent: some View {
        switch selection ?? .general {
        case .general: GeneralSettingsView()
        case .downloads: DownloadSettingsView()
        case .storage: StorageSettingsView()
        case .runtime: RuntimeSettingsView()
        case .controllers: ControllerSettingsView()
        case .fullscreen: ConsoleModeSettingsView()
        case .overlay: GameOverlaySettingsView()
        case .integrations: DiscordSettingsView()
        case .advanced: AdvancedSettingsView()
        }
    }
}
