import Foundation
import SwiftUI

struct FrameGenerationStatusView: View {
    let applicationID: UUID
    let showsStatistics: Bool

    @State private var coordinator = FrameGenerationCoordinator.shared

    var body: some View {
        let state = coordinator.state(for: applicationID)
        let statistics = coordinator.statistics(for: applicationID)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack")
                    .foregroundStyle(tint(for: state))
                Text("Frame generation")
                    .font(.headline)
                Spacer()
                Text(label(for: state))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint(for: state))
            }

            switch state {
            case .running:
                if showsStatistics {
                    HStack(spacing: 18) {
                        metric("Input", value: statistics.inputFPS, symbol: "arrow.down")
                        metric("Generated", value: statistics.generatedFPS, symbol: "sparkles")
                        metric("Output", value: statistics.outputFPS, symbol: "arrow.up")
                    }
                    if statistics.droppedInputFrames > 0 || statistics.skippedGeneratedFrames > 0 {
                        Text("Dropped \(statistics.droppedInputFrames) input · skipped \(statistics.skippedGeneratedFrames) generated")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(String(format: "Average generation %.1f ms", statistics.averageGenerationTimeMS))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Active. Performance statistics are hidden in this game's settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .preparing:
                Text("Resolving the game window and preparing the MetalFX pipeline…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .unavailable(let reason), .failed(let reason):
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .inactive:
                Text("Inactive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.55)) }
    }

    private func metric(_ title: String, value: Double, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "%.0f FPS", value))
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }

    private func label(for state: FrameGenerationState) -> String {
        switch state {
        case .inactive: "Off"
        case .preparing: "Preparing"
        case .running: "Running"
        case .unavailable: "Unavailable"
        case .failed: "Failed"
        }
    }

    private func tint(for state: FrameGenerationState) -> Color {
        switch state {
        case .inactive: .secondary
        case .preparing: .orange
        case .running: .green
        case .unavailable, .failed: .orange
        }
    }
}
