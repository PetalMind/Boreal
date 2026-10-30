import Foundation

nonisolated enum ExternalModDiscovery {
    static func makeMod(
        adapter: ModGameAdapter,
        name: String,
        detectionKey: String,
        files: [URL],
        relativeTo root: URL,
        contentType: ModContentType,
        deployStrategy: ModDeployStrategy = .manual,
        requirements: [String] = [],
        plugins: [BethesdaPlugin] = [],
        fileManager: FileManager = .default
    ) -> InstalledMod? {
        let records = files.compactMap { url -> ModFile? in
            guard let relativePath = relativePath(of: url, from: root),
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
                values.isRegularFile == true,
                values.isSymbolicLink != true,
                let sha256 = try? RuntimeSecurity.sha256(of: url)
            else { return nil }
            return ModFile(relativePath: relativePath, sha256: sha256, size: Int64(values.fileSize ?? 0))
        }.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        guard !records.isEmpty else { return nil }

        let key = normalizedPath(detectionKey)
        return InstalledMod(
            id: ModIdentity.externalID(adapter: adapter, detectionKey: key),
            name: name,
            enabled: true,
            priority: Int.max,
            stagingRelativePath: "",
            installedAt: latestModificationDate(of: files, fileManager: fileManager) ?? .now,
            files: records,
            plugins: plugins,
            contentType: contentType,
            deployStrategy: deployStrategy,
            requirements: requirements,
            warnings: ["Detected in the installed game files. Boreal does not own or deploy these files."],
            installationSource: .external,
            detectionKey: key
        )
    }

    static func relativePath(of url: URL, from root: URL) -> String? {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return nil }
        let relative = String(path.dropFirst(rootPath.count + 1)).replacingOccurrences(of: "\\", with: "/")
        let components = relative.split(separator: "/").map(String.init)
        guard !relative.isEmpty,
            !relative.hasPrefix("/"),
            !components.contains(".."),
            !components.contains(where: { $0.contains(":") })
        else { return nil }
        return relative
    }

    /// Returns the comparison form used by deployment manifests and game
    /// filesystem scans. Manifests created by older builds may contain a
    /// leading `./` or Windows separators, while URLs use the host platform's
    /// separator and path casing is not significant for the supported games.
    static func normalizedPath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .joined(separator: "/")
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }

    static func latestModificationDate(of files: [URL], fileManager: FileManager = .default) -> Date? {
        files.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max()
    }

    static func merge(
        managed: [InstalledMod],
        discovered: [InstalledMod]
    ) -> [InstalledMod] {
        var result = managed.filter { !$0.isExternallyDetected }
        let storedExternal = managed.reduce(into: [String: InstalledMod]()) { result, mod in
            guard mod.isExternallyDetected, let detectionKey = mod.detectionKey else { return }
            result[normalizedPath(detectionKey)] = mod
        }
        for detected in discovered {
            var value = detected
            if let previous = storedExternal[normalizedPath(detected.detectionKey ?? "")] {
                value.id = previous.id
                if detected.contentType == .witcher3Mod {
                    value.enabled = previous.enabled
                    value.priority = previous.priority
                }
            }
            result.append(value)
        }
        return result
    }
}
