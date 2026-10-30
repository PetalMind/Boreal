import Foundation

/// Shared persistence safeguards used by game-specific mod services.
nonisolated enum ModProfileStorage {
    static func loadDeployment(at url: URL, gameID: UUID) throws -> ModDeploymentManifest {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return .empty(gameID: gameID)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(ModDeploymentManifest.self, from: data)
        guard manifest.gameID == gameID, manifest.schemaVersion == 1 else {
            throw ModManagerError.deploymentFailed(
                "The deployment record belongs to another game or uses an unsupported format. Restore its backup before changing mods.")
        }
        return manifest
    }

    /// A profile must be saved first. Unreadable sibling profiles retain the
    /// package so a damaged index cannot cause deletion of another profile's data.
    static func removeUnreferencedPackage(
        _ mod: InstalledMod,
        in gameDirectory: URL,
        excludingProfileID: String
    ) throws {
        let fileManager = FileManager.default
        let directory = gameDirectory.appending(path: "profiles", directoryHint: .isDirectory)
        guard let profiles = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for url in profiles where url.pathExtension.caseInsensitiveCompare("json") == .orderedSame {
            guard url.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(excludingProfileID) != .orderedSame else { continue }
            guard let data = try? Data(contentsOf: url),
                let profile = try? decoder.decode(ModProfile.self, from: data)
            else { return }
            if profile.mods.contains(where: { other in
                other.id == mod.id
                    || ExternalModDiscovery.normalizedPath(other.stagingRelativePath) == ExternalModDiscovery.normalizedPath(mod.stagingRelativePath)
                    || (other.archiveRelativePath != nil && mod.archiveRelativePath != nil
                        && ExternalModDiscovery.normalizedPath(other.archiveRelativePath!) == ExternalModDiscovery.normalizedPath(mod.archiveRelativePath!))
            }) {
                return
            }
        }
        let staging = try packageURL(mod.stagingRelativePath, category: "Staging", in: gameDirectory)
        let archive = try mod.archiveRelativePath.map { try packageURL($0, category: "Archives", in: gameDirectory) }
        // Resolve and validate both paths before deleting either resource.
        for url in [archive, staging].compactMap({ $0 }) where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private static func packageURL(_ path: String, category: String, in root: URL) throws -> URL {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/")
        guard !normalized.hasPrefix("/"), !normalized.contains("\0"),
            parts.count > 1, parts.first == Substring(category),
            !parts.contains(".."), !parts.contains(where: { $0.contains(":") })
        else {
            throw ModManagerError.invalidRelativePath(path)
        }
        let url = parts.reduce(root) { $0.appending(path: String($1)) }
        let allowed = root.appending(path: category).resolvingSymlinksInPath().standardizedFileURL.path
        let storageRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard allowed.hasPrefix(storageRoot + "/"),
            url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(allowed + "/")
        else {
            throw ModManagerError.invalidRelativePath(path)
        }
        return url
    }
}
