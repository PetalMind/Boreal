import SwiftUI

struct DownloadsView: View {
    private let downloads = [
        RuntimeDownload(name: "Boreal Runtime", detail: "Required to open Windows applications", state: .available, symbol: "gearshape.2.fill"),
        RuntimeDownload(name: "Metal Graphics Support", detail: "Optimized graphics for Apple Silicon", state: .available, symbol: "display"),
        RuntimeDownload(name: "Compatibility Profiles", detail: "Recommended app configurations", state: .installed, symbol: "checkmark.seal.fill")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Components").font(.title2).fontWeight(.semibold)
                    Text("Boreal downloads shared components only when an app needs them.").foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    ForEach(Array(downloads.enumerated()), id: \.element.id) { index, download in
                        HStack(spacing: 14) {
                            Image(systemName: download.symbol)
                                .font(.title2)
                                .foregroundStyle(download.state == .installed ? Color.green : Color.accentColor)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(download.name).font(.headline)
                                Text(download.detail).font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if download.state == .installed { Text(download.state.rawValue).foregroundStyle(.secondary) }
                            else { Button("Download") { }.buttonStyle(.bordered) }
                        }.padding(16)
                        if index < downloads.count - 1 { Divider().padding(.leading, 66) }
                    }
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(.separator.opacity(0.7), lineWidth: 0.5))
            }
            .padding(32)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }
}
