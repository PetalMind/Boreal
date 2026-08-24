import AppKit
import SwiftUI

struct AppDetailView: View {
    @Environment(BorealStore.self) private var store
    let app: WindowsApplication
    let didRemove: () -> Void
    @State private var showsRemoveConfirmation = false
    @State private var showsAdvanced = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 24) {
                    AppIconView(symbol: app.iconSymbol, size: 112)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(app.name).font(.largeTitle).fontWeight(.semibold)
                        Text(app.publisher).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button(app.status == .running ? "Stop" : "Open", systemImage: app.status == .running ? "stop.fill" : "play.fill") { store.toggleRunning(app.id) }
                                .buttonStyle(.borderedProminent).controlSize(.large)
                            Menu {
                                Button("Show in Finder", systemImage: "folder") { revealInstaller() }
                                Button("Check Health", systemImage: "stethoscope") { }
                                if app.status == .running {
                                    Button("Force Quit", systemImage: "xmark.octagon", role: .destructive) { store.forceQuit(app.id) }
                                }
                                Divider()
                                Button("Remove App…", systemImage: "trash", role: .destructive) { showsRemoveConfirmation = true }
                            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                        }.padding(.top, 5)
                    }
                    Spacer()
                    if app.status == .running { Label("Running", systemImage: "circle.fill").foregroundStyle(.green).font(.callout) }
                }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 48, verticalSpacing: 24) {
                    GridRow {
                        infoGroup("Compatibility") {
                            CompatibilityLabel(rating: app.compatibility)
                            Text(app.compatibility == .unknown ? "Not tested yet." : "Configuration verified by Boreal.").font(.caption).foregroundStyle(.secondary)
                        }
                        infoGroup("Environment") {
                            Text(app.windowsVersion)
                            Text(store.environment(id: app.environmentID)?.runtime ?? "Runtime unavailable").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        infoGroup("Graphics") {
                            Text(app.graphics)
                            Text("Boreal chooses the recommended renderer.").font(.caption).foregroundStyle(.secondary)
                        }
                        infoGroup("Storage") {
                            Text(store.formattedBytes(app.storageBytes))
                            Text("Application and environment data").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                DisclosureGroup("Configuration", isExpanded: $showsAdvanced) {
                    VStack(spacing: 2) {
                        DetailRow(title: "Windows version", value: app.windowsVersion, symbol: "rectangle.on.rectangle")
                        DetailRow(title: "Graphics", value: app.graphics, symbol: "display")
                        DetailRow(title: "Environment", value: store.environment(id: app.environmentID)?.name ?? "Unavailable", symbol: "externaldrive")
                        DetailRow(title: "Executable", value: URL(fileURLWithPath: app.executablePath).lastPathComponent, symbol: "doc.badge.gearshape")
                    }.padding(.top, 10)
                }
            }
            .padding(36)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .confirmationDialog("Remove \(app.name)?", isPresented: $showsRemoveConfirmation) {
            Button("Remove App and Environment", role: .destructive) { store.removeApplication(app.id); didRemove() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This removes the app from Boreal. The original setup file is not deleted.") }
    }

    private func infoGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.headline); content() }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func revealInstaller() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.installerPath)])
    }
}
