import Foundation
import SwiftUI
import AppKit
import ImageIO

enum BorealMotion {
    static let instant = Animation.easeOut(duration: 0.10)
    static let hover = Animation.easeOut(duration: 0.16)
    static let control = Animation.easeOut(duration: 0.20)
    static let stateChange = Animation.easeInOut(duration: 0.24)
    static let panel = Animation.easeInOut(duration: 0.28)
    static let navigation = Animation.spring(duration: 0.36, bounce: 0.06)
    static let hero = Animation.spring(duration: 0.46, bounce: 0.04)
    static let reorder = Animation.spring(duration: 0.30, bounce: 0.12)
}

struct BorealMotionEnvironment {
    let reduceMotion: Bool

    var instant: Animation? { reduceMotion ? .easeOut(duration: 0.08) : BorealMotion.instant }
    var hover: Animation? { reduceMotion ? .easeOut(duration: 0.08) : BorealMotion.hover }
    var control: Animation? { reduceMotion ? .easeOut(duration: 0.08) : BorealMotion.control }
    var stateChange: Animation? { reduceMotion ? .easeOut(duration: 0.08) : BorealMotion.stateChange }
    var panel: Animation? { reduceMotion ? .easeOut(duration: 0.12) : BorealMotion.panel }
    var navigation: Animation? { reduceMotion ? .easeOut(duration: 0.12) : BorealMotion.navigation }
    var hero: Animation? { reduceMotion ? .easeOut(duration: 0.14) : BorealMotion.hero }
    var reorder: Animation? { reduceMotion ? .easeOut(duration: 0.12) : BorealMotion.reorder }

    init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
    }
}

struct FavoriteButton: View {
    let isFavorite: Bool
    let isHovered: Bool
    let revealsOnHover: Bool
    let showsBackground: Bool
    let favoriteColor: Color
    let inactiveColor: Color
    let helpText: String
    let accessibilityText: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var symbolScale: CGFloat = 1
    @State private var ringScale: CGFloat = 1
    @State private var ringOpacity = 0.0
    @State private var pendingPressAction: DispatchWorkItem?
    @State private var pendingSettle: DispatchWorkItem?
    @State private var pendingRingFade: DispatchWorkItem?

    private var motion: BorealMotionEnvironment {
        BorealMotionEnvironment(reduceMotion: reduceMotion)
    }

    private var stateAnimation: Animation? {
        reduceMotion ? motion.control : motion.control?.speed(1.4)
    }

    private var targetOpacity: Double {
        guard revealsOnHover, !isFavorite else { return 1 }
        return isHovered || isFocused ? 0.75 : 0
    }

    init(
        isFavorite: Bool,
        isHovered: Bool = true,
        revealsOnHover: Bool = false,
        showsBackground: Bool = true,
        favoriteColor: Color = .red,
        inactiveColor: Color = .white,
        helpText: String,
        accessibilityText: String,
        action: @escaping () -> Void
    ) {
        self.isFavorite = isFavorite
        self.isHovered = isHovered
        self.revealsOnHover = revealsOnHover
        self.showsBackground = showsBackground
        self.favoriteColor = favoriteColor
        self.inactiveColor = inactiveColor
        self.helpText = helpText
        self.accessibilityText = accessibilityText
        self.action = action
    }

    var body: some View {
        Button(action: triggerFavoriteChange) {
            ZStack {
                if showsBackground {
                    Circle()
                        .fill(.black.opacity(0.34))
                }

                Circle()
                    .stroke(favoriteColor.opacity(0.34), lineWidth: 1)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)
                    .allowsHitTesting(false)

                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(isFavorite ? favoriteColor : inactiveColor)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            }
            .font(.title3.weight(.semibold))
            .frame(width: 34, height: 34)
            .scaleEffect(symbolScale)
            .shadow(color: .black.opacity(0.7), radius: 3)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .contentShape(Circle())
        .opacity(targetOpacity)
        .animation(motion.hover, value: isHovered)
        .animation(motion.hover, value: isFocused)
        .animation(stateAnimation, value: isFavorite)
        .allowsHitTesting(isFavorite || !revealsOnHover || isHovered || isFocused)
        .help(Text(helpText))
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
    }

    private func triggerFavoriteChange() {
        pendingPressAction?.cancel()
        pendingSettle?.cancel()
        pendingRingFade?.cancel()
        pendingPressAction = nil
        pendingSettle = nil
        pendingRingFade = nil

        guard !reduceMotion else {
            action()
            return
        }

        let becomesFavorite = !isFavorite
        withAnimation(motion.instant?.speed(1.25)) {
            symbolScale = becomesFavorite ? 0.88 : 0.90
            ringScale = 0.92
            ringOpacity = 0
        }

        let pressAction = DispatchWorkItem {
            pendingPressAction = nil
            action()

            withAnimation(stateAnimation) {
                symbolScale = becomesFavorite ? 1.12 : 0.90
                ringScale = 1.08
                ringOpacity = becomesFavorite ? 0.16 : 0
            }

            let settle = DispatchWorkItem {
                withAnimation(stateAnimation) {
                    symbolScale = 1
                    ringScale = 1.16
                }
                pendingSettle = nil
            }

            let ringFade = DispatchWorkItem {
                withAnimation(motion.instant) {
                    ringScale = 1.14
                    ringOpacity = 0
                }
                pendingRingFade = nil
            }

            pendingSettle = settle
            pendingRingFade = ringFade
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: settle)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07, execute: ringFade)
        }

        pendingPressAction = pressAction
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: pressAction)
    }
}

struct BorealActivityPulse: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isActive && !reduceMotion && isPulsing ? 0.72 : 1)
            .overlay {
                Circle()
                    .stroke(.green.opacity(0.62), lineWidth: 1.5)
                    .opacity(isPulsing ? 0.18 : (isActive && !reduceMotion ? 0.62 : 0))
                    .allowsHitTesting(false)
            }
            .animation(
                isActive && !reduceMotion ? BorealMotion.stateChange.speed(0.28).repeatForever(autoreverses: false) : BorealMotion.instant,
                value: isPulsing
            )
            .onAppear { isPulsing = isActive && !reduceMotion }
            .onChange(of: isActive) { _, value in
                isPulsing = value && !reduceMotion
            }
            .onChange(of: reduceMotion) { _, value in
                isPulsing = isActive && !value
            }
    }
}

extension View {
    func borealActivityPulse(isActive: Bool) -> some View {
        modifier(BorealActivityPulse(isActive: isActive))
    }
}

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
            placeholder.overlay { BorealArtworkLoadingIndicator() }
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

private struct BorealArtworkLoadingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .trim(from: 0.12, to: 0.86)
            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            .frame(width: 18, height: 18)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(.linear(duration: 0.85).repeatForever(autoreverses: false), value: isAnimating)
            .onAppear { isAnimating = true }
            .accessibilityLabel("Loading artwork")
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
