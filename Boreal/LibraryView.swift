import SwiftUI

struct LibraryView: View {
    @Environment(BorealStore.self) private var store
    let searchText: String
    let style: ContentView.LibraryStyle
    let installAction: () -> Void
    let importAction: (URL) -> Void
    let selectAction: (UUID) -> Void

    private var filteredApps: [WindowsApplication] {
        guard !searchText.isEmpty else { return store.applications }
        return store.applications.filter { $0.name.localizedStandardContains(searchText) || $0.publisher.localizedStandardContains(searchText) }
    }

    var body: some View {
        Group {
            if store.applications.isEmpty { BorealEmptyState(action: installAction) }
            else if filteredApps.isEmpty { ContentUnavailableView.search(text: searchText) }
            else if style == .grid { grid }
            else { list }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, ["exe", "msi"].contains(url.pathExtension.lowercased()) else { return false }
            importAction(url)
            return true
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 190), spacing: 30)], spacing: 30) {
                ForEach(filteredApps) { app in
                    Button { selectAction(app.id) } label: {
                        VStack(spacing: 11) {
                            AppIconView(symbol: app.iconSymbol, size: 104)
                            VStack(spacing: 3) {
                                Text(app.name).font(.headline).lineLimit(1)
                                Text(app.status.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(app.status == .running ? "Stop" : "Open", systemImage: app.status == .running ? "stop.fill" : "play.fill") { store.toggleRunning(app.id) }
                        Divider()
                        Button("Remove", systemImage: "trash", role: .destructive) { store.removeApplication(app.id) }
                    }
                    .accessibilityLabel("\(app.name), \(app.status.rawValue)")
                }
            }
            .padding(32)
            .frame(maxWidth: 1100)
        }
    }

    private var list: some View {
        Table(filteredApps) {
            TableColumn("Name") { app in
                Button { selectAction(app.id) } label: {
                    HStack(spacing: 10) {
                        AppIconView(symbol: app.iconSymbol, size: 32)
                        Text(app.name)
                    }
                }.buttonStyle(.plain)
            }
            TableColumn("Status") { Text($0.status.rawValue).foregroundStyle($0.status == .running ? .green : .primary) }.width(min: 90, ideal: 120)
            TableColumn("Environment", value: \.windowsVersion).width(min: 110, ideal: 150)
            TableColumn("Last Opened") { app in
                Text(app.lastOpened?.formatted(.relative(presentation: .named)) ?? "Never").foregroundStyle(.secondary)
            }.width(min: 110, ideal: 140)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }
}
