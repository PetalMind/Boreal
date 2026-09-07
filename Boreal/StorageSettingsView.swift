import AppKit
import SwiftUI

struct StorageSettingsView: View {
    @Environment(BorealStore.self) private var store
    @State private var report: BorealStorageReport?
    @State private var isScanning = false

    private let categories: [BorealStorageCategory] = [.games, .environments, .runtimes, .caches, .downloads, .logs]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                overviewCard
                if let report {
                    categoryCards(report)
                    safetyCard
                } else if isScanning {
                    loadingCard
                } else {
                    emptyCard
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await scan() }
    }

    private var overviewCard: some View {
        SettingsCard("Storage", subtitle: "See what Boreal is using without touching game data or prefixes.", symbol: "internaldrive.fill") {
            if let report {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Boreal-managed data")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(formatted(report.totalBytes))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Last scanned")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(report.scannedAt, style: .relative)
                            .font(.callout.monospacedDigit())
                    }
                }
                StorageUsageBar(report: report, categories: categories)
                    .frame(height: 12)
                    .padding(.vertical, 8)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(categories) { category in
                        storageSummaryRow(category, bytes: report.bytes(for: category))
                    }
                }
            } else {
                HStack {
                    ProgressView()
                    Text(isScanning ? "Scanning Boreal-managed locations…" : "Storage has not been scanned yet.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            Divider().padding(.vertical, 4)
            HStack {
                Text("Managed location")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 16)
                Text(store.managedStorageLayout.rootURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.open(store.managedStorageLayout.rootURL)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack {
                Spacer()
                Button("Scan Storage", systemImage: "arrow.clockwise") {
                    Task { await scan() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isScanning)
            }
        }
    }

    private func categoryCards(_ report: BorealStorageReport) -> some View {
        ForEach(categories) { category in
            let items = report.items(for: category)
            SettingsCard(category.title, subtitle: category.subtitle, symbol: category.symbol) {
                if items.isEmpty {
                    Text("No measured data in this category.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(items.prefix(8))) { item in
                        StorageItemRow(item: item, formatted: formatted(item.bytes))
                        if item.id != items.prefix(8).last?.id { Divider() }
                    }
                    if items.count > 8 {
                        Text("Showing the 8 largest locations.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 7)
                    }
                }
            }
        }
    }

    private var safetyCard: some View {
        SettingsCard("Storage safety", subtitle: "The report separates data by the consequence of removing it.", symbol: "checkmark.shield.fill") {
            StorageRiskRow(title: "Safe", description: "Downloads and logs can be recreated or removed without deleting a game or prefix.", color: .green)
            Divider()
            StorageRiskRow(title: "Regeneratable", description: "Shader and metadata caches may be rebuilt; the next launch can take longer.", color: .orange)
            Divider()
            StorageRiskRow(title: "Destructive", description: "Games, environments and runtimes are shown for information only and are never part of automatic cleanup.", color: .red)
        }
    }

    private var loadingCard: some View {
        SettingsCard("Scanning Storage", subtitle: "Reading only locations already managed or recorded by Boreal.", symbol: "magnifyingglass") {
            ProgressView().controlSize(.small)
        }
    }

    private var emptyCard: some View {
        SettingsCard("Storage", subtitle: "Scan to measure Boreal-managed files.", symbol: "internaldrive") {
            Text("No scan has been completed yet.").foregroundStyle(.secondary)
        }
    }

    private func storageSummaryRow(_ category: BorealStorageCategory, bytes: Int64) -> some View {
        HStack(spacing: 8) {
            Image(systemName: category.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(category.title)
                .font(.callout)
            Spacer(minLength: 6)
            Text(formatted(bytes))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func scan() async {
        guard !isScanning else { return }
        isScanning = true
        let layout = store.managedStorageLayout
        let applications = store.applications
        let storeGames = store.storeGames
        let environments = store.environments
        let value = await Task.detached(priority: .utility) {
            BorealStorageScanner.scan(layout: layout, applications: applications, storeGames: storeGames, environments: environments)
        }.value
        report = value
        isScanning = false
    }

    private func formatted(_ bytes: Int64) -> String {
        store.formattedBytes(bytes)
    }
}

private struct StorageUsageBar: View {
    let report: BorealStorageReport
    let categories: [BorealStorageCategory]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(categories) { category in
                    let fraction = report.totalBytes > 0 ? CGFloat(report.bytes(for: category)) / CGFloat(report.totalBytes) : 0
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color(for: category))
                        .frame(width: max(fraction > 0 ? 4 : 0, geometry.size.width * fraction))
                }
                if report.totalBytes == 0 { RoundedRectangle(cornerRadius: 4).fill(.quaternary) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private func color(for category: BorealStorageCategory) -> Color {
        switch category {
        case .games: .cyan
        case .environments: .indigo
        case .runtimes: .purple
        case .caches: .orange
        case .downloads: .green
        case .logs: .gray
        }
    }
}

private struct StorageItemRow: View {
    let item: BorealStorageItem
    let formatted: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.category.symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                if let detail = item.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Text(item.isEstimated ? "≈ \(formatted)" : formatted)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
    }
}

private struct StorageRiskRow: View {
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 7)
    }
}
