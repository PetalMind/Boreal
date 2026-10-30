import AppKit
import CryptoKit
import Foundation
import ImageIO

private actor DiscoveryArtworkGate {
    private var active = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []

    func acquire() async -> Bool {
        guard !Task.isCancelled else { return false }
        if active < 6 {
            active += 1
            return true
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled { continuation.resume(returning: false) } else { waiters.append((id, continuation)) }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }

    func release() {
        if waiters.isEmpty { active = max(0, active - 1) } else { waiters.removeFirst().continuation.resume(returning: true) }
    }
}

actor DiscoveryImagePipeline {
    static let shared = DiscoveryImagePipeline()

    private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 96 * 1_024 * 1_024
        cache.evictsObjectsWithDiscardedContent = true
        return cache
    }()
    private let diskCacheDirectory: URL?
    private static let diskCacheLimitBytes: UInt64 = 512 * 1_024 * 1_024
    private static let diskCacheTrimTargetBytes: UInt64 = 384 * 1_024 * 1_024
    private var diskWriteCount = 0
    private struct ImageLoad {
        let id: UUID
        let task: Task<NSImage?, Never>
        var consumers: Set<UUID>
    }
    private var inFlight: [URL: ImageLoad] = [:]
    private var failedLoads: [URL: Date] = [:]
    private let downloadGate = DiscoveryArtworkGate()

    init() {
        diskCacheDirectory = ApplicationDataLocation.logicalRoot.appending(
            path: "Discovery/Artwork",
            directoryHint: .isDirectory
        )
    }

    func image(for url: URL, maxPixelSize: Int) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if let cached = readDiskImage(for: url, maxPixelSize: maxPixelSize) {
            cache.setObject(cached, forKey: url as NSURL, cost: Self.imageCost(cached))
            return cached
        }
        guard !Task.isCancelled else { return nil }
        if let load = inFlight[url] { return await consume(load, for: url, maxPixelSize: maxPixelSize) }
        if let failedAt = failedLoads[url], Date.now.timeIntervalSince(failedAt) < 120 { return nil }

        let gate = downloadGate
        let task = Task.detached(priority: .utility) { () -> NSImage? in
            guard await gate.acquire() else { return nil }
            guard !Task.isCancelled else {
                await gate.release()
                return nil
            }
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            let image: NSImage?
            if let (data, response) = try? await URLSession.shared.data(for: request),
                (response as? HTTPURLResponse)?.statusCode == 200, !Task.isCancelled
            {
                image = Self.downsampledImage(from: data, maxPixelSize: maxPixelSize)
            } else {
                image = nil
            }
            await gate.release()
            return image
        }
        let load = ImageLoad(id: UUID(), task: task, consumers: [])
        inFlight[url] = load
        return await consume(load, for: url, maxPixelSize: maxPixelSize)
    }

    private func consume(_ load: ImageLoad, for url: URL, maxPixelSize: Int) async -> NSImage? {
        let consumer = UUID()
        inFlight[url]?.consumers.insert(consumer)
        let image = await withTaskCancellationHandler {
            await load.task.value
        } onCancel: {
            Task { await self.removeConsumer(consumer, loadID: load.id, for: url) }
        }
        removeConsumer(consumer, loadID: load.id, for: url)
        guard !Task.isCancelled else { return nil }
        if let image {
            failedLoads.removeValue(forKey: url)
            if cache.object(forKey: url as NSURL) == nil {
                cache.setObject(image, forKey: url as NSURL, cost: Self.imageCost(image))
                writeDiskImage(image, for: url, maxPixelSize: maxPixelSize)
            }
        } else {
            failedLoads = failedLoads.filter { Date.now.timeIntervalSince($0.value) < 120 }
            if failedLoads.count >= 256, let oldest = failedLoads.min(by: { $0.value < $1.value })?.key {
                failedLoads.removeValue(forKey: oldest)
            }
            failedLoads[url] = .now
        }
        return image
    }

    private func removeConsumer(_ consumer: UUID, loadID: UUID, for url: URL) {
        guard var load = inFlight[url], load.id == loadID else { return }
        load.consumers.remove(consumer)
        if load.consumers.isEmpty {
            load.task.cancel()
            inFlight[url] = nil
        } else {
            inFlight[url] = load
        }
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

    private func diskURL(for url: URL, maxPixelSize: Int) -> URL? {
        guard let diskCacheDirectory else { return nil }
        let key = "\(url.absoluteString)|\(maxPixelSize)"
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return diskCacheDirectory.appending(path: "\(digest).png", directoryHint: .notDirectory)
    }

    private func readDiskImage(for url: URL, maxPixelSize: Int) -> NSImage? {
        guard let diskURL = diskURL(for: url, maxPixelSize: maxPixelSize),
            let data = try? Data(contentsOf: diskURL),
            let image = NSImage(data: data)
        else { return nil }
        return image
    }

    private func writeDiskImage(_ image: NSImage, for url: URL, maxPixelSize: Int) {
        guard let diskURL = diskURL(for: url, maxPixelSize: maxPixelSize),
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else { return }
        do {
            try FileManager.default.createDirectory(
                at: diskURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try pngData.write(to: diskURL, options: .atomic)
            diskWriteCount += 1
            if diskWriteCount.isMultiple(of: 25) {
                trimDiskCacheIfNeeded()
            }
        } catch {
            // Artwork can always be fetched again when the optional disk cache is unavailable.
        }
    }

    private func trimDiskCacheIfNeeded() {
        guard let diskCacheDirectory,
            let files = try? FileManager.default.contentsOfDirectory(
                at: diskCacheDirectory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        else { return }
        let entries = files.compactMap { url -> (url: URL, size: UInt64, date: Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                let size = values.fileSize,
                let date = values.contentModificationDate
            else { return nil }
            return (url, UInt64(max(0, size)), date)
        }
        var total = entries.reduce(UInt64(0)) { $0 + $1.size }
        guard total > Self.diskCacheLimitBytes else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard total > Self.diskCacheTrimTargetBytes else { break }
            try? FileManager.default.removeItem(at: entry.url)
            total = total > entry.size ? total - entry.size : 0
        }
    }
}
