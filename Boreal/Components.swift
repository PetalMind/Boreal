import Foundation
import SwiftUI
import AppKit
import ImageIO

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

struct ControllerConsoleModeDialog: View {
    let confirm: () -> Void
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.cyan)
                        .frame(width: 48, height: 48)
                        .background(.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Controller detected")
                            .font(.title2.weight(.semibold))
                        Text("Start console mode?")
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Console mode switches Boreal to fullscreen and makes the library easier to control with a controller.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button("Not now", action: dismiss)
                        .keyboardShortcut(.cancelAction)
                    Button("Start console mode", action: confirm)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
            .frame(width: 500)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 28, y: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand(perform: dismiss)
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

enum ArtworkKind: Sendable {
    case cover
    case hero
}

enum ArtworkDisplayMode: Sendable {
    case automatic
    case fill
    case fit
}

struct GameArtworkView: View {
    let game: StoreLibraryGame
    var width: CGFloat = 156
    var height: CGFloat = 218
    var cornerRadius: CGFloat = 16
    var usesCustomArtwork = true
    var kind: ArtworkKind = .cover
    var displayMode: ArtworkDisplayMode = .automatic
    var showsChrome = true

    @State private var remoteImage: NSImage?
    @State private var remoteLoadFinished = false

    var body: some View {
        Group {
            if showsChrome {
                artworkSurface
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 12, y: 7)
            } else {
                artworkSurface
                    .frame(width: width, height: height)
                    .clipped()
            }
        }
        .task(id: remoteURL?.absoluteString ?? "") {
            await loadRemoteArtwork()
        }
        .accessibilityHidden(true)
    }

    private var artworkSurface: some View {
        ZStack {
            LinearGradient(
                colors: [.indigo.opacity(0.85), .cyan.opacity(0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            content
        }
    }

    @ViewBuilder private var content: some View {
        if let image = localImage ?? remoteImage {
            renderedArtwork(image)
        } else if remoteURL != nil && !remoteLoadFinished {
            placeholder.overlay { ProgressView().tint(.white) }
        } else {
            placeholder.overlay {
                if remoteURL != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .padding(8)
                        .foregroundStyle(.yellow)
                }
            }
        }
    }

    @ViewBuilder private func renderedArtwork(_ image: NSImage) -> some View {
        switch resolvedDisplayMode(for: image) {
        case .fill, .automatic:
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .fit:
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .blur(radius: 22)
                    .scaleEffect(1.12)
                    .opacity(0.72)

                Color.black.opacity(0.18)

                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var localImage: NSImage? {
        if usesCustomArtwork,
           let image = ArtworkImageCache.customImage(
               processedPath: game.customArtworkPath,
               originalPath: game.customArtworkOriginalPath
           ) {
            return image
        }
        if kind == .hero, remoteURL != nil {
            return nil
        }
        if let path = game.artworkPath, let image = ArtworkImageCache.image(at: path) {
            return image
        }
        return nil
    }

    private var remoteURL: URL? {
        let value: String?
        switch kind {
        case .cover:
            value = game.portraitImageURL ?? game.headerImageURL ?? game.backgroundImageURL
        case .hero:
            value = game.backgroundImageURL ?? game.headerImageURL ?? game.portraitImageURL
        }
        return value.flatMap(URL.init(string:))
    }

    private func resolvedDisplayMode(for image: NSImage) -> ArtworkDisplayMode {
        switch displayMode {
        case .fill, .fit:
            return displayMode
        case .automatic:
            guard kind == .cover,
                  let aspectRatio = imageAspectRatio(for: image) else { return .fill }
            return abs(aspectRatio - (2.0 / 3.0)) < 0.12 ? .fill : .fit
        }
    }

    private func imageAspectRatio(for image: NSImage) -> CGFloat? {
        let representation = image.representations.max {
            ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh)
        }
        let width = CGFloat(representation?.pixelsWide ?? Int(image.size.width))
        let height = CGFloat(representation?.pixelsHigh ?? Int(image.size.height))
        guard width > 0, height > 0 else { return nil }
        return width / height
    }

    @MainActor
    private func loadRemoteArtwork() async {
        remoteImage = nil
        remoteLoadFinished = false
        guard localImage == nil, let remoteURL else {
            remoteLoadFinished = true
            return
        }
        let image = await BorealArtworkImagePipeline.shared.image(for: remoteURL, maxPixelSize: 1600)
        guard !Task.isCancelled else { return }
        remoteImage = image
        remoteLoadFinished = true
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "gamecontroller.fill").font(.system(size: min(width, height) * 0.27))
            Text(game.provider.rawValue.uppercased()).font(.caption2).fontWeight(.bold).tracking(1.4)
        }
        .foregroundStyle(.white.opacity(0.9))
    }
}

private actor BorealArtworkImagePipeline {
    static let shared = BorealArtworkImagePipeline()

    private let cache = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    func image(for url: URL, maxPixelSize: Int) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if let task = inFlight[url] { return await task.value }

        let task = Task.detached(priority: .utility) { () -> NSImage? in
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  !Task.isCancelled else { return nil }
            return Self.downsampledImage(from: data, maxPixelSize: maxPixelSize)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            cache.setObject(image, forKey: url as NSURL, cost: Self.imageCost(image))
        }
        return image
    }

    private static func downsampledImage(from data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: thumbnail, size: .zero)
    }

    private static func imageCost(_ image: NSImage) -> Int {
        let representation = image.representations.first
        let width = representation?.pixelsWide ?? Int(image.size.width)
        let height = representation?.pixelsHigh ?? Int(image.size.height)
        return max(1, width * height * 4)
    }
}

@MainActor
enum ArtworkImageCache {
    private static let images = NSCache<NSString, NSImage>()

    static func image(at path: String) -> NSImage? {
        let key = path as NSString
        if let image = images.object(forKey: key) { return image }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        images.setObject(image, forKey: key, cost: imageCost(image))
        images.totalCostLimit = 192 * 1_024 * 1_024
        return image
    }

    static func customImage(processedPath: String?, originalPath: String?) -> NSImage? {
        if let processedPath, let image = image(at: processedPath) { return image }
        if let originalPath, let image = image(at: originalPath) { return image }
        return nil
    }

    private static func imageCost(_ image: NSImage) -> Int {
        guard let representation = image.representations.first else { return 0 }
        return representation.pixelsWide * representation.pixelsHigh * 4
    }
}

struct StorePlatformBadge: View {
    let game: StoreLibraryGame

    var body: some View {
        if game.supportsNativeMacOS == true {
            NativeMacOSBadge()
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

struct NativeMacOSBadge: View {
    var compact = false

    var body: some View {
        Label("Natywna", systemImage: "apple.logo")
            .font(compact ? .caption2.weight(.semibold) : .callout.weight(.semibold))
            .foregroundStyle(.green)
            .padding(.horizontal, compact ? 7 : 9)
            .padding(.vertical, compact ? 4 : 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().stroke(Color.green.opacity(0.45), lineWidth: 1) }
            .shadow(color: .black.opacity(compact ? 0.25 : 0), radius: 5, y: 2)
            .accessibilityLabel("Natywna wersja macOS")
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
    var body: some View {
        Label { Text(rating.localizedTitle) } icon: { Image(systemName: rating.symbol) }
            .foregroundStyle(color)
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

struct MacCompatibilityBadge: View {
    let rating: CompatibilityRating
    var compact = false

    var body: some View {
        Label {
            if compact {
                Text(rating.localizedTitle)
            } else {
                HStack(spacing: 4) {
                    Text(.Compatibility.macViaWine)
                    Text(rating.localizedTitle)
                }
            }
        } icon: {
            Image(systemName: rating.symbol)
        }
            .font(compact ? .caption2.weight(.semibold) : .callout.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, compact ? 7 : 9)
            .padding(.vertical, compact ? 4 : 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().stroke(color.opacity(0.45), lineWidth: 1) }
            .shadow(color: .black.opacity(compact ? 0.25 : 0), radius: 5, y: 2)
            .accessibilityLabel(Text("\(String(localized: .Compatibility.macViaWine)): \(String(localized: rating.localizedTitle))"))
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
