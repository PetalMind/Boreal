import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DownloadSettingsView: View {
    @AppStorage(StoreDownloadConcurrency.workersDefaultsKey)
    private var preferredWorkerCount = StoreDownloadConcurrency.automaticPreference

    private var effectiveWorkerCount: Int {
        StoreDownloadConcurrency.effectiveWorkerCount(for: preferredWorkerCount)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SettingsCard(
                    .Settings.parallelDownloadsTitle,
                    subtitle: .Settings.parallelDownloadsSubtitle,
                    symbol: "arrow.left.arrow.right"
                ) {
                    SettingsRow(.Settings.parallelDownloadsModeLabel) {
                        Picker(selection: $preferredWorkerCount) {
                            Text(.Settings.parallelDownloadsAutomatic)
                                .tag(StoreDownloadConcurrency.automaticPreference)
                            ForEach(
                                StoreDownloadConcurrency.minimumWorkers...StoreDownloadConcurrency.maximumWorkers,
                                id: \.self
                            ) { workerCount in
                                Text("\(workerCount)").tag(workerCount)
                            }
                        } label: {
                            EmptyView()
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                    Divider()
                    SettingsRow(.Settings.parallelDownloadsCurrentLimit) {
                        Text(effectiveWorkerCount, format: .number)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    Text(.Settings.parallelDownloadsHelp)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
