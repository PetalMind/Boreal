import AppKit
import SwiftUI

struct WineMSyncBuildSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var dependencyPrefix = URL(fileURLWithPath: "/usr/local", isDirectory: true)
    @State private var preparesLibrariesAutomatically = true
    let build: (URL?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Wine MSync builder", systemImage: "hammer.fill").font(.title2.weight(.semibold))
            Text("Boreal downloads verified Wine 9.15 sources and the official MSync patch, compiles a new WoW64 runtime, checks MSync startup and imports the result.")
            Text("This is an experimental Wine 9.15 build. It does not include D3DMetal. Existing runtimes and game environments are preserved. After preparation, select Wine MSync in the game's runtime settings.")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            Text("Intel build libraries").font(.headline)
            Toggle("Prepare Intel libraries automatically", isOn: $preparesLibrariesAutomatically)
            if preparesLibrariesAutomatically {
                Text("Boreal builds x86_64 libraries and headers from verified sources in a private directory and includes them in the finished Wine runtime. No system installation is needed.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text(dependencyPrefix.path).font(.callout.monospaced()).textSelection(.enabled)
                    Spacer()
                    Button("Choose folder…") { chooseDependencyPrefix() }
                }
                Text("Select the prefix containing lib/libfreetype.dylib, lib/libgnutls.dylib and lib/pkgconfig for x86_64. Keep these libraries installed while using the compiled runtime. Required tools are checked before downloading sources.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Link("MSync project and license", destination: URL(string: "https://github.com/marzent/wine-msync")!)
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Download, build and import") { build(preparesLibrariesAutomatically ? nil : dependencyPrefix) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 580)
    }

    private func chooseDependencyPrefix() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Intel build libraries")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = dependencyPrefix
        if panel.runModal() == .OK, let selected = panel.url { dependencyPrefix = selected }
    }
}
