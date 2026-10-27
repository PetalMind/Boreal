import Foundation

nonisolated enum ModFileDestinationRoot: String, Codable, CaseIterable, Sendable, Hashable {
    case data
    case gameRoot

    func key(for path: String) -> String {
        switch self {
        case .data:
            path.lowercased()
        case .gameRoot:
            "@game-root:/\(path.lowercased())"
        }
    }

    func displayPath(_ path: String) -> String {
        switch self {
        case .data: path
        case .gameRoot: "Game Root/\(path)"
        }
    }
}

nonisolated enum ModFileDestination {
    static func url(
        root: ModFileDestinationRoot,
        relativePath: String,
        gameRoot: URL,
        dataRoot: URL
    ) -> URL {
        let base = root == .data ? dataRoot : gameRoot
        return relativePath.split(separator: "/").reduce(base) { $0.appending(path: String($1)) }
    }
}

nonisolated struct SkyrimScriptExtenderArchiveEntry: Sendable {
    let path: String
    let url: URL
}

nonisolated struct SkyrimScriptExtenderPayloadFile: Sendable {
    let source: URL
    let relativePath: String
    let destinationRoot: ModFileDestinationRoot
    let stagedSourcePath: String
}

nonisolated struct SkyrimScriptExtenderInspection: Sendable {
    let detectedRoot: String
    let files: [SkyrimScriptExtenderPayloadFile]
    let warnings: [String]
    let canInstallAutomatically: Bool
}

nonisolated enum SkyrimScriptExtenderArchive {
    private struct Candidate {
        let root: String
        let loader: SkyrimScriptExtenderArchiveEntry
        let runtimeLibraries: [(entry: SkyrimScriptExtenderArchiveEntry, version: String)]
        let scripts: [SkyrimScriptExtenderArchiveEntry]
        let dataFiles: [SkyrimScriptExtenderArchiveEntry]
    }

    static func inspect(
        entries: [SkyrimScriptExtenderArchiveEntry],
        installedGameVersion: String?
    ) -> SkyrimScriptExtenderInspection? {
        let candidates = entries.compactMap { loader -> Candidate? in
            let loaderName = URL(fileURLWithPath: loader.path).lastPathComponent
            guard loaderName.caseInsensitiveCompare("skse64_loader.exe") == .orderedSame else {
                return nil
            }
            let root = parentPath(of: loader.path)
            let libraries = entries.compactMap { entry -> (entry: SkyrimScriptExtenderArchiveEntry, version: String)? in
                guard parentPath(of: entry.path).caseInsensitiveCompare(root) == .orderedSame,
                      let version = runtimeVersion(
                          fromLibraryName: URL(fileURLWithPath: entry.path).lastPathComponent
                      ) else {
                    return nil
                }
                return (entry, version)
            }
            let dataPrefix = joined(root, "Data/")
            let dataFiles = entries.filter { entry in
                entry.path.lowercased().hasPrefix(dataPrefix.lowercased())
            }
            let scripts = dataFiles.filter { entry in
                let path = entry.path.replacingOccurrences(of: "\\", with: "/")
                let scriptsPrefix = joined(root, "Data/Scripts/")
                return path.lowercased().hasPrefix(scriptsPrefix.lowercased())
                    && URL(fileURLWithPath: path).pathExtension.caseInsensitiveCompare("pex") == .orderedSame
            }
            guard !libraries.isEmpty || !scripts.isEmpty else { return nil }
            return Candidate(
                root: root,
                loader: loader,
                runtimeLibraries: libraries,
                scripts: scripts,
                dataFiles: dataFiles
            )
        }

        guard candidates.count == 1, let candidate = candidates.first else { return nil }

        let expectedVersion = canonicalVersion(installedGameVersion)
        let matchingLibraries = expectedVersion.map { expected in
            candidate.runtimeLibraries.filter { $0.version == expected }
        } ?? []
        let selectedLibraries: [SkyrimScriptExtenderArchiveEntry]
        if matchingLibraries.count == 1 {
            selectedLibraries = [matchingLibraries[0].entry]
        } else {
            selectedLibraries = candidate.runtimeLibraries.map(\.entry)
        }

        var warnings: [String] = []
        if candidate.runtimeLibraries.isEmpty {
            warnings.append("The archive is missing the version-specific SKSE library needed by Skyrim.")
        } else if let expectedVersion {
            if matchingLibraries.isEmpty {
                let available = candidate.runtimeLibraries.map(\.version).sorted().joined(separator: ", ")
                warnings.append(
                    "This SKSE archive is for Skyrim \(available), but the installed game is \(expectedVersion). "
                        + "Choose the matching SKSE download."
                )
            } else if matchingLibraries.count > 1 {
                warnings.append(
                    "The archive contains more than one SKSE library for Skyrim \(expectedVersion), "
                        + "so Boreal can’t choose one safely."
                )
            }
        } else {
            warnings.append("Boreal couldn’t read the installed Skyrim version, so it can’t verify this SKSE package.")
        }
        if candidate.scripts.isEmpty {
            warnings.append("The archive is missing SKSE’s Papyrus scripts under Data/Scripts.")
        }

        let payload = [candidate.loader] + selectedLibraries + candidate.dataFiles
        let files = payload.map { entry -> SkyrimScriptExtenderPayloadFile in
            let isRootFile = entry.path.caseInsensitiveCompare(candidate.loader.path) == .orderedSame
                || selectedLibraries.contains(where: { $0.path.caseInsensitiveCompare(entry.path) == .orderedSame })
            if isRootFile {
                let filename = URL(fileURLWithPath: entry.path).lastPathComponent
                return SkyrimScriptExtenderPayloadFile(
                    source: entry.url,
                    relativePath: filename,
                    destinationRoot: .gameRoot,
                    stagedSourcePath: "GameRoot/\(filename)"
                )
            }
            let dataPrefix = joined(candidate.root, "Data/")
            let normalizedPath = entry.path.replacingOccurrences(of: "\\", with: "/")
            let relativePath = String(normalizedPath.dropFirst(dataPrefix.count))
            return SkyrimScriptExtenderPayloadFile(
                source: entry.url,
                relativePath: relativePath,
                destinationRoot: .data,
                stagedSourcePath: "Data/\(relativePath)"
            )
        }

        return SkyrimScriptExtenderInspection(
            detectedRoot: "Game folder + Data/Scripts",
            files: files,
            warnings: warnings,
            canInstallAutomatically: warnings.isEmpty
        )
    }

    static func matchingLoader(
        in gameRoot: URL,
        gameVersion: String?,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let expectedVersion = canonicalVersion(gameVersion) else { return nil }
        let loader = gameRoot.appending(path: "skse64_loader.exe")
        guard isRegularFile(loader, fileManager: fileManager),
              let files = try? fileManager.contentsOfDirectory(
                  at: gameRoot,
                  includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return nil
        }

        let matchingLibraries = files.filter { file in
            isRegularFile(file, fileManager: fileManager)
                && runtimeVersion(fromLibraryName: file.lastPathComponent) == expectedVersion
        }
        return matchingLibraries.count == 1 ? loader : nil
    }

    private static func isRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
        guard let values = try? url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private static func runtimeVersion(fromLibraryName name: String) -> String? {
        let lowercased = name.lowercased()
        guard lowercased.hasPrefix("skse64_"), lowercased.hasSuffix(".dll") else { return nil }
        let versionPart = lowercased.dropFirst("skse64_".count).dropLast(".dll".count)
        let components = versionPart.split(separator: "_")
        guard components.count == 3, components.allSatisfy({ Int($0) != nil }) else { return nil }
        return components.joined(separator: ".")
    }

    private static func canonicalVersion(_ value: String?) -> String? {
        guard let value else { return nil }
        let components = value.split(separator: ".").compactMap { Int($0) }
        guard components.count >= 3 else { return nil }
        return components.prefix(3).map(String.init).joined(separator: ".")
    }

    private static func parentPath(of path: String) -> String {
        let value = path.replacingOccurrences(of: "\\", with: "/")
        guard let slash = value.lastIndex(of: "/") else { return "" }
        return String(value[..<slash])
    }

    private static func joined(_ root: String, _ suffix: String) -> String {
        root.isEmpty ? suffix : "\(root)/\(suffix)"
    }
}
