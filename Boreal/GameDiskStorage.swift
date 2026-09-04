import Foundation

nonisolated enum GameDiskStorageCategory: String, CaseIterable, Sendable {
    case gameFiles, prefix, shaders, downloads, snapshots

    var title: String {
        switch self {
        case .gameFiles: "Game files"
        case .prefix: "Prefix"
        case .shaders: "Shaders"
        case .downloads: "Downloads"
        case .snapshots: "Snapshots"
        }
    }
}

nonisolated struct GameDiskStorageItem: Identifiable, Sendable {
    let category: GameDiskStorageCategory
    let bytes: Int64?
    let paths: [URL]
    var id: String { category.rawValue }
}

nonisolated struct GameDiskStorageReport: Sendable {
    let items: [GameDiskStorageItem]

    func item(_ category: GameDiskStorageCategory) -> GameDiskStorageItem? {
        items.first { $0.category == category }
    }
}

/// Discovers only data that Boreal owns or can identify as a cache. The scanner
/// deliberately does not treat arbitrary folders named "Cache" as removable.
nonisolated enum GameDiskStorage {
    static func report(gameURL: URL?, prefixURL: URL?, applicationSupportURL: URL?, fileManager: FileManager = .default) -> GameDiskStorageReport {
        let gameRoots = gameURL.map { [$0] } ?? []
        let prefixRoots = prefixURL.map { [$0] } ?? []
        let supportRoots = applicationSupportURL.map { [$0.appending(path: "Downloads"), $0.appending(path: ".downloads"), $0.appending(path: "Snapshots")] } ?? []
        let shaderRoots = unique(
            cacheDirectories(in: gameURL, fileManager: fileManager)
                + cacheDirectories(in: prefixURL, fileManager: fileManager)
        )
        let snapshotRoots = unique(
            snapshotDirectories(under: applicationSupportURL?.appending(path: "Snapshots"), fileManager: fileManager)
                + snapshotDirectories(under: prefixURL?.appending(path: "Snapshots"), fileManager: fileManager)
        )
        return GameDiskStorageReport(items: [
            item(.gameFiles, roots: gameRoots, removable: false, fileManager: fileManager),
            item(.prefix, roots: prefixRoots, removable: false, fileManager: fileManager),
            GameDiskStorageItem(category: .shaders, bytes: allocatedSize(of: shaderRoots, fileManager: fileManager), paths: shaderRoots),
            GameDiskStorageItem(category: .downloads, bytes: allocatedSize(of: supportRoots.filter { $0.lastPathComponent.lowercased().contains("download") }, fileManager: fileManager), paths: supportRoots.filter { $0.lastPathComponent.lowercased().contains("download") }),
            GameDiskStorageItem(category: .snapshots, bytes: allocatedSize(of: snapshotRoots, fileManager: fileManager), paths: snapshotRoots)
        ])
    }

    static func remove(_ category: GameDiskStorageCategory, from report: GameDiskStorageReport, fileManager: FileManager = .default) throws {
        guard category != .gameFiles, category != .prefix,
              let item = report.item(category) else { return }
        for path in item.paths where fileManager.fileExists(atPath: path.path) {
            try fileManager.removeItem(at: path)
        }
    }

    private static func item(_ category: GameDiskStorageCategory, roots: [URL], removable: Bool, fileManager: FileManager) -> GameDiskStorageItem {
        _ = removable
        return GameDiskStorageItem(category: category, bytes: allocatedSize(of: roots, fileManager: fileManager), paths: roots)
    }

    private static func allocatedSize(of roots: [URL], fileManager: FileManager) -> Int64? {
        let values = roots.compactMap { GameStorage.allocatedSize(of: $0, fileManager: fileManager) }
        let total = values.reduce(0, +)
        return total > 0 ? total : nil
    }

    private static func cacheDirectories(in root: URL?, fileManager: FileManager) -> [URL] {
        guard let root, fileManager.fileExists(atPath: root.path),
              let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants]) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent.lowercased()
            if name == "shadercache" || name == "shader_cache" || name == "d3dscache" || name == "dxvk-cache" {
                result.append(url)
            }
        }
        return result
    }

    private static func snapshotDirectories(under root: URL?, fileManager: FileManager) -> [URL] {
        guard let root, fileManager.fileExists(atPath: root.path),
              let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }
        return children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private static func unique(_ paths: [URL]) -> [URL] {
        var seen = Set<String>()
        return paths.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
