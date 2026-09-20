import Foundation
import SwiftUI

struct FrameGenerationStatusView: View {
    let applicationID: UUID

    @State private var coordinator = FrameGenerationCoordinator.shared

    var body: some View {
        let state = coordinator.state(for: applicationID)
        let evidence = coordinator.runtimeEvidence(for: applicationID)

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

            Text("OptiFG · FSR Frame Generation")
                .font(.subheadline.weight(.medium))
            Text("Runs inside the game's DX12 process. The real game window remains the only presentation and input surface.")
                .font(.caption)
                .foregroundStyle(.secondary)

            switch state {
            case .active, .frameGenerationAvailable:
                Text("OptiScaler reported a usable frame-generation path.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .optiFGInitialized:
                Text("OptiFG initialized; waiting for active frame-generation work from the game.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .preparing:
                Text("Preparing the in-process OptiScaler backend…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .injected:
                Text("OptiScaler is injected; waiting for the game's upscaler and frame-generation initialization.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .waitingForUpscaler:
                Text("OptiFG is waiting for compatible temporal upscaler input.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .degraded(let reason), .failed(let reason):
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .inactive:
                Text("Inactive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let evidence {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Runtime evidence")
                        .font(.caption.weight(.semibold))
                    Text("Install: \(evidence.installation.displayName) · Process: \(evidence.process.displayName) · Log: \(evidence.log.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let detail = evidence.detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.55)) }
    }

    private func label(for state: FrameGenerationState) -> String {
        switch state {
        case .inactive: "Off"
        case .preparing: "Preparing"
        case .injected: "Injected"
        case .waitingForUpscaler: "Waiting"
        case .frameGenerationAvailable: "Ready"
        case .optiFGInitialized: "Initialized"
        case .active: "Active"
        case .degraded: "Degraded"
        case .failed: "Failed"
        }
    }

    private func tint(for state: FrameGenerationState) -> Color {
        switch state {
        case .inactive: .secondary
        case .preparing, .injected, .waitingForUpscaler, .optiFGInitialized, .degraded: .orange
        case .frameGenerationAvailable, .active: .green
        case .failed: .red
        }
    }
}
