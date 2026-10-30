import AVKit
import AppKit
import SwiftUI

enum StoreMediaItem: Hashable, Identifiable {
    case screenshot(URL)
    case video(StoreVideo)

    var id: String {
        switch self {
        case .screenshot(let url): "screenshot:\(url.absoluteString)"
        case .video(let video): "video:\(video.id)"
        }
    }

    var thumbnailURL: URL? {
        switch self {
        case .screenshot(let url): url
        case .video(let video): video.thumbnailURL.flatMap(URL.init(string:))
        }
    }

    var title: String {
        switch self {
        case .screenshot: "Screenshot"
        case .video(let video): video.name
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .screenshot: "Open screenshot"
        case .video(let video): "Play \(video.name)"
        }
    }

    var isVideo: Bool {
        if case .video = self { return true }
        return false
    }
}

struct StoreMediaSelection: Identifiable {
    let items: [StoreMediaItem]
    let initialIndex: Int
    var id: String { "\(items.map(\.id).joined(separator: "|"))#\(initialIndex)" }
}

private struct GalleryScreenshotView: View {
    let url: URL

    var body: some View {
        ZStack {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(1.12)
                        .blur(radius: 32)
                        .opacity(0.18)
                case .failure, .empty:
                    Color.black
                @unknown default:
                    Color.black
                }
            }
            .overlay(Color(red: 0.015, green: 0.03, blue: 0.05).opacity(0.62))
            .overlay(Color.black.opacity(0.22))

            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    ContentUnavailableView("Screenshot Unavailable", systemImage: "photo.badge.exclamationmark")
                case .empty:
                    ProgressView()
                @unknown default:
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.34))
        .clipped()
    }
}

struct StoreMediaThumbnail: View {
    let item: StoreMediaItem
    let width: CGFloat

    var body: some View {
        ZStack {
            if let url = item.thumbnailURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        Rectangle()
                            .fill(.background.secondary)
                            .overlay { ProgressView().controlSize(.small) }
                    @unknown default:
                        Rectangle().fill(.background.secondary)
                    }
                }
            } else {
                placeholder
            }

            if item.isVideo {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(9)
                    .background(.black.opacity(0.46), in: Circle())
            }
        }
        .frame(width: width, height: width * 9 / 16)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.indigo.opacity(0.62), Color.black.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "photo")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
        }
    }
}

struct StoreMediaViewer: View {
    private let mediaAspectRatio: CGFloat = 16.0 / 9.0
    private let headerHeight: CGFloat = 64
    private let metadataHeight: CGFloat = 58
    private let filmstripHeight: CGFloat = 104

    let selection: StoreMediaSelection
    let game: StoreLibraryGame
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: BorealMotionEnvironment {
        BorealMotionEnvironment(reduceMotion: reduceMotion)
    }

    @State private var currentIndex: Int
    @State private var player = AVPlayer()
    @State private var isPlaying = false
    @State private var showsImmersiveViewer = false

    init(selection: StoreMediaSelection, game: StoreLibraryGame, onDismiss: @escaping () -> Void) {
        self.selection = selection
        self.game = game
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: min(max(selection.initialIndex, 0), max(selection.items.count - 1, 0)))
    }

    var body: some View {
        Group {
            if showsImmersiveViewer {
                immersiveViewer
            } else {
                galleryContent
            }
        }
        .preferredColorScheme(.dark)
        .background { gallerySurface }
        .onAppear(perform: preparePlayer)
        .onChange(of: currentIndex) { preparePlayer() }
        .onDisappear { player.pause() }
        .onExitCommand {
            if showsImmersiveViewer {
                showsImmersiveViewer = false
            } else {
                onDismiss()
            }
        }
        .background {
            Button("Previous media", action: showPrevious)
                .keyboardShortcut(.leftArrow, modifiers: [])
                .hidden()
            Button("Next media", action: showNext)
                .keyboardShortcut(.rightArrow, modifiers: [])
                .hidden()
            Button("Play or pause video", action: togglePlayback)
                .keyboardShortcut(.space, modifiers: [])
                .hidden()
            Button("Toggle fullscreen", action: toggleImmersiveViewer)
                .keyboardShortcut(.return, modifiers: [.command])
                .hidden()
            Button("Toggle fullscreen", action: toggleImmersiveViewer)
                .keyboardShortcut("f", modifiers: [])
                .hidden()
        }
    }

    private var gallerySurface: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay {
                LinearGradient(
                    colors: [
                        Color(red: 0.055, green: 0.05, blue: 0.07),
                        Color(red: 0.025, green: 0.025, blue: 0.035),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
    }

    private var galleryContent: some View {
        VStack(spacing: 0) {
            galleryHeader
                .frame(height: headerHeight)
                .frame(maxWidth: .infinity)
            galleryMediaStage
            galleryMetadata
                .frame(height: metadataHeight)
                .frame(maxWidth: .infinity)
            Divider()
                .opacity(0.36)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            galleryFilmstrip
                .frame(height: filmstripHeight)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private var galleryHeader: some View {
        HStack(spacing: 12) {
            GameArtworkView(
                game: game,
                width: 38,
                height: 38,
                kind: .cover,
                displayMode: .automatic,
                showsChrome: false
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(game.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Media")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer(minLength: 16)

            Text("\(currentIndex + 1) / \(selection.items.count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .padding(.trailing, 4)

            galleryHeaderButton(
                title: "Fullscreen",
                symbol: "arrow.up.left.and.arrow.down.right",
                action: toggleImmersiveViewer
            )
            .help("Fullscreen (⌘↩)")

            galleryHeaderButton(title: "Close", symbol: "xmark", action: onDismiss)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .background(Color.white.opacity(0.025))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.28)
        }
    }

    private func galleryHeaderButton(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.white.opacity(0.09), lineWidth: 1)
        }
        .accessibilityLabel(title)
    }

    private var galleryMediaStage: some View {
        ZStack {
            mediaContent
                .id(currentItem.id)
                .transition(.opacity)

            if selection.items.count > 1 {
                HStack {
                    galleryNavigationButton(
                        title: "Previous media",
                        symbol: "chevron.left",
                        action: showPrevious
                    )
                    Spacer()
                    galleryNavigationButton(
                        title: "Next media",
                        symbol: "chevron.right",
                        action: showNext
                    )
                }
                .padding(.horizontal, 24)
            }
        }
        .aspectRatio(mediaAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.25))
        .clipped()
        .animation(motion.control, value: currentItem.id)
    }

    @ViewBuilder private var mediaContent: some View {
        switch currentItem {
        case .screenshot(let url):
            Button {
                showsImmersiveViewer = true
            } label: {
                GalleryScreenshotView(url: url)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open screenshot in fullscreen viewer")
        case .video:
            videoContent
        }
    }

    private var videoContent: some View {
        ZStack {
            mediaBackdrop
            VideoPlayer(player: player)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var mediaBackdrop: some View {
        if let url = currentItem.thumbnailURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black
                }
            }
            .scaleEffect(1.14)
            .blur(radius: 30)
            .overlay(Color(red: 0.015, green: 0.03, blue: 0.05).opacity(0.65))
            .overlay(Color.black.opacity(0.32))
        } else {
            Color.black
        }
    }

    private var galleryMetadata: some View {
        HStack(alignment: .center) {
            Text(currentItem.isVideo ? "Video" : "Image")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))

            Spacer(minLength: 20)

            VStack(alignment: .trailing, spacing: 3) {
                Text(currentItem.isVideo ? currentItem.title : game.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                Text(game.developer ?? game.provider.rawValue)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 28)
        .background(Color.black.opacity(0.12))
    }

    private var galleryFilmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(Array(selection.items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            selectMedia(at: index)
                        } label: {
                            StoreMediaThumbnail(item: item, width: 120)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(
                                            index == currentIndex
                                                ? Color.accentColor
                                                : .white.opacity(0.1),
                                            lineWidth: index == currentIndex ? 2 : 1
                                        )
                                }
                                .shadow(
                                    color: index == currentIndex
                                        ? Color.accentColor.opacity(0.32)
                                        : .clear,
                                    radius: 4
                                )
                                .opacity(index == currentIndex ? 1 : 0.74)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.accessibilityTitle)
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                scrollToCurrentItem(using: proxy, animated: false)
            }
            .onChange(of: currentIndex) {
                scrollToCurrentItem(using: proxy, animated: true)
            }
        }
        .background(Color.black.opacity(0.14))
    }

    private var immersiveViewer: some View {
        GeometryReader { geometry in
            let availableWidth = max(0, geometry.size.width - 48)
            let availableHeight = max(0, geometry.size.height - 48)
            let viewportWidth = min(availableWidth, availableHeight * mediaAspectRatio)
            let viewportHeight = viewportWidth / mediaAspectRatio

            ZStack {
                Color.black.opacity(0.96)

                immersiveMediaContent
                    .id(currentItem.id)
                    .transition(.opacity)
                    .frame(width: viewportWidth, height: viewportHeight)

                if selection.items.count > 1 {
                    HStack {
                        galleryNavigationButton(
                            title: "Previous media",
                            symbol: "chevron.left",
                            action: showPrevious
                        )
                        Spacer()
                        galleryNavigationButton(
                            title: "Next media",
                            symbol: "chevron.right",
                            action: showNext
                        )
                    }
                    .padding(.horizontal, 24)
                }

                VStack {
                    Spacer()
                    Text("\(currentIndex + 1) / \(selection.items.count)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(.bottom, 18)
                }
            }
            .animation(motion.control, value: currentItem.id)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var immersiveMediaContent: some View {
        switch currentItem {
        case .screenshot(let url):
            Button {
                showsImmersiveViewer = false
            } label: {
                GalleryScreenshotView(url: url)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Return to media gallery")
        case .video:
            videoContent
        }
    }

    private func galleryNavigationButton(
        title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.18), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private var currentItem: StoreMediaItem {
        guard selection.items.indices.contains(currentIndex) else {
            return selection.items.first ?? .screenshot(URL(fileURLWithPath: "/"))
        }
        return selection.items[currentIndex]
    }

    private func preparePlayer() {
        player.pause()
        isPlaying = false

        guard case .video(let video) = currentItem,
            let url = URL(string: video.videoURL)
        else {
            player.replaceCurrentItem(with: nil)
            return
        }

        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
        isPlaying = true
    }

    private func togglePlayback() {
        guard currentItem.isVideo else { return }

        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func toggleImmersiveViewer() {
        showsImmersiveViewer.toggle()
    }

    private func selectMedia(at index: Int) {
        guard selection.items.indices.contains(index), index != currentIndex else { return }

        withAnimation(motion.control) {
            currentIndex = index
        }
    }

    private func scrollToCurrentItem(using proxy: ScrollViewProxy, animated: Bool) {
        guard selection.items.indices.contains(currentIndex) else { return }

        let action = {
            proxy.scrollTo(selection.items[currentIndex].id, anchor: .center)
        }

        if animated {
            withAnimation(motion.instant, action)
        } else {
            action()
        }
    }

    private func showPrevious() {
        guard !selection.items.isEmpty else { return }
        selectMedia(at: (currentIndex - 1 + selection.items.count) % selection.items.count)
    }

    private func showNext() {
        guard !selection.items.isEmpty else { return }
        selectMedia(at: (currentIndex + 1) % selection.items.count)
    }
}
