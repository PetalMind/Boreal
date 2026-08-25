import SwiftUI
import AppKit

struct BorealGlassBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            RadialGradient(
                colors: [Color.cyan.opacity(0.17), Color.cyan.opacity(0.035), .clear],
                center: .topTrailing,
                startRadius: 24,
                endRadius: 760
            )

            RadialGradient(
                colors: [Color.indigo.opacity(0.15), Color.purple.opacity(0.025), .clear],
                center: .bottomLeading,
                startRadius: 16,
                endRadius: 690
            )

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.22)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct AppIconView: View {
    let symbol: String
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.55, blue: 0.72), Color(red: 0.20, green: 0.30, blue: 0.56)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
        .accessibilityHidden(true)
    }
}

struct GameArtworkView: View {
    let game: StoreLibraryGame
    var width: CGFloat = 156
    var height: CGFloat = 218

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [.indigo.opacity(0.85), .cyan.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
            artwork
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 12, y: 7)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var artwork: some View {
        if let path = game.artworkPath, let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image).resizable().scaledToFill()
        } else if let value = game.portraitImageURL ?? game.headerImageURL, let url = URL(string: value) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { placeholder }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "gamecontroller.fill").font(.system(size: min(width, height) * 0.27))
            Text(game.provider.rawValue.uppercased()).font(.caption2).fontWeight(.bold).tracking(1.4)
        }
        .foregroundStyle(.white.opacity(0.9))
    }
}

struct StorePlatformBadge: View {
    let game: StoreLibraryGame

    var body: some View {
        if game.supportsNativeMacOS == true {
            Label("Native macOS", systemImage: "apple.logo")
                .foregroundStyle(.green)
                .accessibilityLabel("Native macOS version available")
        } else if game.supportsWindows == true {
            Label("Windows via Boreal", systemImage: "wineglass")
                .foregroundStyle(game.compatibility?.tier.rating == .unsupported ? .red : .cyan)
                .accessibilityLabel("Windows version can run through Boreal compatibility")
        } else {
            Label("Platform unknown", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }
}

struct StoreRatingBadge: View {
    let rating: StoreRating?

    var body: some View {
        if let rating, let score = rating.displayScore {
            Label(score, systemImage: "star.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.yellow)
                .help(rating.label ?? "Store rating")
        }
    }
}

struct CompatibilityLabel: View {
    let rating: CompatibilityRating
    var body: some View { Label(rating.rawValue, systemImage: rating.symbol).foregroundStyle(color) }
    private var color: Color {
        switch rating {
        case .excellent: .green
        case .good: .teal
        case .limited: .orange
        case .unknown: .secondary
        case .unsupported: .red
        }
    }
}

struct MacCompatibilityBadge: View {
    let rating: CompatibilityRating
    var compact = false

    var body: some View {
        Label(compact ? rating.rawValue : "Mac via Wine: \(rating.rawValue)", systemImage: rating.symbol)
            .font(compact ? .caption2.weight(.semibold) : .callout.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, compact ? 7 : 9)
            .padding(.vertical, compact ? 4 : 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().stroke(color.opacity(0.45), lineWidth: 1) }
            .shadow(color: .black.opacity(compact ? 0.25 : 0), radius: 5, y: 2)
            .accessibilityLabel("Mac compatibility through Wine: \(rating.rawValue)")
    }

    private var color: Color {
        switch rating {
        case .excellent: .green
        case .good: .teal
        case .limited: .orange
        case .unknown: .secondary
        case .unsupported: .red
        }
    }
}

struct CommunityCompatibilityBadge: View {
    let profile: CommunityCompatibility?
    var compact = false

    var body: some View {
        if let profile {
            Label(profile.tier.title, systemImage: profile.tier.rating.symbol)
                .font(compact ? .caption : .callout)
                .fontWeight(.medium)
                .foregroundStyle(color(profile.tier))
                .padding(.horizontal, compact ? 7 : 9)
                .padding(.vertical, compact ? 3 : 5)
                .background(color(profile.tier).opacity(0.12), in: Capsule())
                .accessibilityLabel("\(profile.source.rawValue) compatibility: \(profile.tier.title)")
        } else {
            Label("Not rated", systemImage: "questionmark.circle")
                .font(compact ? .caption : .callout)
                .foregroundStyle(.secondary)
        }
    }

    private func color(_ tier: CompatibilityTier) -> Color {
        switch tier.rating {
        case .excellent: .green
        case .good: .teal
        case .limited: .orange
        case .unsupported: .red
        case .unknown: .secondary
        }
    }
}

struct ApplicationStatusLabel: View {
    let status: ApplicationStatus
    var subtle = false

    var body: some View {
        Label {
            Text(status.rawValue)
        } icon: {
            if status.isBusy {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: subtle ? 7 : 9, weight: .bold))
            }
        }
        .font(subtle ? .caption : .callout)
        .foregroundStyle(color)
        .accessibilityLabel("Status: \(status.rawValue)")
    }

    private var symbol: String {
        switch status {
        case .running: "circle.fill"
        case .needsAttention: "exclamationmark.triangle.fill"
        case .unavailable: "xmark.circle.fill"
        default: "circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .running: .green
        case .needsAttention: .orange
        case .unavailable: .red
        case .preparing, .starting, .installing: .accentColor
        case .ready: .secondary
        }
    }
}

struct BorealErrorSheet: View {
    let issue: BorealIssue
    var retry: (() -> Void)?
    let dismiss: () -> Void
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text(issue.title).font(.title2).fontWeight(.semibold)
                    Text(issue.stage).foregroundStyle(.secondary)
                    Text(issue.recovery)
                }
            }
            DisclosureGroup("Details", isExpanded: $showsDetails) {
                Text(issue.technicalDetails)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
            HStack {
                if let retry {
                    Button("Try Again", systemImage: "arrow.clockwise") {
                        dismiss()
                        retry()
                    }
                }
                Spacer()
                Button("Done", action: dismiss)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 500)
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    var symbol: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value)
            }
            Spacer()
        }
        .padding(.vertical, 5)
    }
}

struct BorealEmptyState: View {
    let action: () -> Void
    let steamAction: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Boreal", systemImage: "sparkles.rectangle.stack")
        } description: {
            VStack(spacing: 6) {
                Text("Windows apps. At home on your Mac.")
                Text("Import your Steam Library or install a Windows app.")
            }
        } actions: {
            HStack {
                Button("Import Steam Library", systemImage: "arrow.triangle.2.circlepath", action: steamAction)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button("Install App", systemImage: "plus", action: action).controlSize(.large)
            }
            Text("You can also drop an .exe or .msi file here").font(.caption).foregroundStyle(.secondary)
        }
    }
}
