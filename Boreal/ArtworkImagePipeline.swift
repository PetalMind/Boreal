import AppKit
import Foundation
import ImageIO

actor BorealArtworkImagePipeline {
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
                !Task.isCancelled
            else { return nil }
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
