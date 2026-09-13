import Foundation

// MARK: - Layered installed-game discovery

/// The discovery source is intentionally separate from the store provider.
/// A registry or shortcut can identify a GOG game even when the GOG account is
/// disconnected, while a Steam manifest must still be handed back to the
/// Steam-specific launch/install path.
nonisolated enum GameDiscoverySource: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case borealEnvironment
    case steamManifest
    case gogManifest
    case epicManifest
    case registry
    case shortcut
    case filesystem

    var id: Self { self }

    var title: String {
        switch self {
        case .borealEnvironment: "Boreal environments"
        case .steamManifest: "Steam manifest"
        case .gogManifest: "GOG manifest"
        case .epicManifest: "Epic manifest"
        case .registry: "Windows Registry"
        case .shortcut: "Windows shortcut"
        case .filesystem: "Filesystem fallback"
        }
    }

    var symbol: String {
        switch self {
        case .borealEnvironment: "shippingbox"
        case .steamManifest: "gamecontroller.fill"
        case .gogManifest: "g.square.fill"
        case .epicManifest: "e.square.fill"
        case .registry: "list.bullet.rectangle"
        case .shortcut: "arrow.up.right.square"
        case .filesystem: "doc.text.magnifyingglass"
        }
    }

    /// Manifest sources are intentionally first. The number is used only for
    /// deterministic merging and never replaces the confidence score.
    var priority: Int {
        switch self {
        case .steamManifest, .gogManifest, .epicManifest: 0
        case .registry: 1
        case .shortcut: 2
        case .borealEnvironment: 3
        case .filesystem: 4
        }
    }
}

nonisolated enum GameDiscoveryAutomaticImportMode: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case highConfidence
    case all
    case never

    var id: Self { self }

    var title: String {
        switch self {
        case .highConfidence: "Only high-confidence matches"
        case .all: "All discovered matches"
        case .never: "Never automatically add"
        }
    }
}

nonisolated struct GameDiscoveryEvidence: Hashable, Sendable {
    let points: Int
    let message: String
}

nonisolated struct GameDiscoveryCandidate: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let source: GameDiscoverySource
    let sources: [GameDiscoverySource]
    let storeReference: StoreReference?
    let installPath: URL
    let executablePath: URL
    let environmentID: UUID?
    let score: Int
    let reasons: [String]
    let penalties: [String]

    var confidenceTitle: String {
        switch score {
        case 90...: "High confidence"
        case 60..<90: "Likely match"
        case 30..<60: "Needs confirmation"
        default: "Ignored"
        }
    }

    var isAutomaticallyImportable: Bool { score >= 90 }

    var sourceTitle: String {
        sources.map(\.title).joined(separator: " · ")
    }
}

nonisolated struct GameDiscoveryConfiguration: Codable, Hashable, Sendable {
    static let defaultsKey = "gameDiscovery.configuration"

    var enabledSources: Set<GameDiscoverySource>
    var customRoots: [URL]
    var automaticImportMode: GameDiscoveryAutomaticImportMode

    static let `default` = GameDiscoveryConfiguration(
        enabledSources: Set(GameDiscoverySource.allCases),
        customRoots: [],
        automaticImportMode: .highConfidence
    )

    static func load(from defaults: UserDefaults = .standard) -> GameDiscoveryConfiguration {
        guard let data = defaults.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return .default }
        return value
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

nonisolated struct GameDiscoveryEnvironment: Sendable, Hashable {
    let id: UUID
    let rootURL: URL
    let prefixURL: URL
}

nonisolated struct GameDiscoveryContext: Sendable {
    let homeURL: URL
    let applicationSupportURL: URL
    let borealGamesRoot: URL
    let environments: [GameDiscoveryEnvironment]
    let customRoots: [URL]
    let existingExecutablePaths: Set<String>
    let existingInstallPaths: Set<String>
    let existingStoreReferences: Set<StoreReference>
}

nonisolated struct GameDiscoveryScanResult: Sendable {
    let candidates: [GameDiscoveryCandidate]
    let scannedAt: Date
    let changedRootCount: Int
}

nonisolated enum GameDiscoveryState: Equatable, Sendable {
    case idle
    case scanning
    case loaded(candidateCount: Int, changedRootCount: Int)
    case failed(String)
}

nonisolated struct GameDiscoveryCache: Codable, Sendable {
    static let currentSchemaVersion = 3

    var schemaVersion = Self.currentSchemaVersion
    var rootSignatures: [String: String] = [:]
    var candidates: [GameDiscoveryCandidate] = []
    var lastScannedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, rootSignatures, candidates, lastScannedAt
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        rootSignatures = try values.decodeIfPresent([String: String].self, forKey: .rootSignatures) ?? [:]
        candidates = try values.decodeIfPresent([GameDiscoveryCandidate].self, forKey: .candidates) ?? []
        lastScannedAt = try values.decodeIfPresent(Date.self, forKey: .lastScannedAt)
    }
}

nonisolated enum GameDiscoveryCacheStore {
    static func load(at url: URL, fileManager: FileManager = .default) -> GameDiscoveryCache {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(GameDiscoveryCache.self, from: data) else {
            return GameDiscoveryCache()
        }
        return value
    }

    static func save(_ cache: GameDiscoveryCache, at url: URL, fileManager: FileManager = .default) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

nonisolated enum GameDiscoveryService {
    static func scan(
        context: GameDiscoveryContext,
        configuration: GameDiscoveryConfiguration,
        cache: GameDiscoveryCache,
        force: Bool = false,
        fileManager: FileManager = .default
    ) -> (result: GameDiscoveryScanResult, cache: GameDiscoveryCache) {
        var updatedCache = cache
        if updatedCache.schemaVersion != GameDiscoveryCache.currentSchemaVersion {
            // The candidate rules are part of the cache contract. Rebuild it
            // after classifier changes so removed system apps cannot survive
            // as stale suggestions.
            updatedCache = GameDiscoveryCache()
        }
        if configuration.enabledSources.isEmpty {
            let scannedAt = Date()
            updatedCache.candidates = []
            updatedCache.lastScannedAt = scannedAt
            return (
                GameDiscoveryScanResult(candidates: [], scannedAt: scannedAt, changedRootCount: 0),
                updatedCache
            )
        }
        var findings: [RawFinding] = []
        var changedRootCount = 0
        var changedScopes: [(root: URL, source: GameDiscoverySource?)] = []

        let environmentChanges = context.environments.filter { environment in
            let key = "environment:\(environment.id.uuidString)"
            let signature = signature(for: environment.prefixURL, fileManager: fileManager)
            let changed = force || updatedCache.rootSignatures[key] != signature
            if let signature { updatedCache.rootSignatures[key] = signature }
            if changed {
                changedRootCount += 1
                changedScopes.append((environment.prefixURL, nil))
            }
            return changed
        }

        if configuration.enabledSources.contains(.borealEnvironment) {
            for environment in environmentChanges {
                findings += BorealEnvironmentDetector.detect(environment: environment, fileManager: fileManager)
            }
        }
        if configuration.enabledSources.contains(.registry) {
            for environment in environmentChanges {
                findings += RegistryDetector.detect(environment: environment, fileManager: fileManager)
            }
        }
        if configuration.enabledSources.contains(.shortcut) {
            for environment in environmentChanges {
                findings += ShortcutDetector.detect(environment: environment, fileManager: fileManager)
            }
        }

        let steamRoots = steamRoots(in: context, fileManager: fileManager)
        for root in steamRoots where shouldScan(root: root, prefix: "steam", cache: &updatedCache, force: force, fileManager: fileManager) {
            changedRootCount += 1
            changedScopes.append((root, .steamManifest))
            if configuration.enabledSources.contains(.steamManifest) {
                findings += SteamManifestDetector.detect(steamRoot: root, fileManager: fileManager)
            }
        }

        var manifestRoots = [
            context.applicationSupportURL.appending(path: "Games/GOG", directoryHint: .isDirectory),
            context.applicationSupportURL.appending(path: "StoreLibraries", directoryHint: .isDirectory),
            context.homeURL.appending(path: "GOG Games", directoryHint: .isDirectory),
        ] + context.customRoots
        manifestRoots += context.environments.map { $0.prefixURL.appending(path: "drive_c", directoryHint: .isDirectory) }
        for root in uniqueURLs(manifestRoots) where shouldScan(root: root, prefix: "gog", cache: &updatedCache, force: force, fileManager: fileManager) {
            changedRootCount += 1
            changedScopes.append((root, .gogManifest))
            if configuration.enabledSources.contains(.gogManifest) {
                findings += GOGManifestDetector.detect(root: root, environmentID: environmentID(for: root, in: context), fileManager: fileManager)
            }
        }

        var epicRoots = [
            context.applicationSupportURL.appending(path: "Games/Epic", directoryHint: .isDirectory),
            context.applicationSupportURL.appending(path: "StoreLibraries", directoryHint: .isDirectory),
            context.applicationSupportURL.appending(path: "Accounts/Epic", directoryHint: .isDirectory),
            context.homeURL.appending(path: ".config/legendary", directoryHint: .isDirectory),
        ] + context.customRoots
        epicRoots += context.environments.flatMap { environment in
            [
                environment.prefixURL.appending(path: "drive_c/ProgramData/Epic/EpicGamesLauncher/Data/Manifests", directoryHint: .isDirectory),
                environment.prefixURL.appending(path: "drive_c/Program Files (x86)/Epic Games/Launcher/Portal/Saved/Data/Manifests", directoryHint: .isDirectory),
                environment.prefixURL.appending(path: "drive_c/Program Files/Epic Games/Launcher/Portal/Saved/Data/Manifests", directoryHint: .isDirectory),
            ]
        }
        for root in uniqueURLs(epicRoots) where shouldScan(root: root, prefix: "epic", cache: &updatedCache, force: force, fileManager: fileManager) {
            changedRootCount += 1
            changedScopes.append((root, .epicManifest))
            if configuration.enabledSources.contains(.epicManifest) {
                let environment = environment(for: root, in: context)
                findings += EpicManifestDetector.detect(
                    root: root,
                    environmentID: environment?.id,
                    prefixURL: environment?.prefixURL,
                    allowedInstallRoots: allowedManifestInstallRoots(in: context),
                    fileManager: fileManager
                )
            }
        }

        if configuration.enabledSources.contains(.filesystem) {
            var fallbackRoots = [
                context.borealGamesRoot,
                context.homeURL.appending(path: "Games", directoryHint: .isDirectory),
                context.homeURL.appending(path: "GOG Games", directoryHint: .isDirectory),
            ] + context.customRoots
            fallbackRoots += context.environments.flatMap { environment in
                [
                    environment.prefixURL.appending(path: "drive_c/Program Files", directoryHint: .isDirectory),
                    environment.prefixURL.appending(path: "drive_c/Program Files (x86)", directoryHint: .isDirectory),
                    environment.prefixURL.appending(path: "drive_c/GOG Games", directoryHint: .isDirectory),
                    environment.prefixURL.appending(path: "drive_c/Games", directoryHint: .isDirectory),
                ]
            }
            for root in uniqueURLs(fallbackRoots) where shouldScan(root: root, prefix: "filesystem", cache: &updatedCache, force: force, fileManager: fileManager) {
                changedRootCount += 1
                changedScopes.append((root, .filesystem))
                findings += FilesystemDetector.detect(
                    root: root,
                    environmentID: environmentID(for: root, in: context),
                    fileManager: fileManager
                )
            }
        }

        // Grouping by installation path first joins manifest, registry,
        // shortcut, and filesystem evidence for the same installation. The
        // second merge below also folds duplicate store records that point at
        // different paths.
        let freshCandidates = mergeCandidates(deduplicate(findings))
        let retainedCandidates = force
            ? []
            : cache.candidates.filter { candidate in
                !changedScopes.contains { scope in isInvalidated(candidate, by: scope) }
            }
        let candidates = mergeCandidates(freshCandidates + retainedCandidates).filter { candidate in
            let executableKey = pathKey(candidate.executablePath)
            let installKey = pathKey(candidate.installPath)
            if context.existingExecutablePaths.contains(executableKey) || context.existingInstallPaths.contains(installKey) {
                return false
            }
            if let reference = candidate.storeReference, context.existingStoreReferences.contains(reference) {
                return false
            }
            return candidate.score >= 30
        }
        updatedCache.candidates = candidates
        updatedCache.lastScannedAt = Date()
        return (
            GameDiscoveryScanResult(candidates: candidates, scannedAt: updatedCache.lastScannedAt ?? Date(), changedRootCount: changedRootCount),
            updatedCache
        )
    }

    private struct RawFinding: Sendable {
        var name: String
        var source: GameDiscoverySource
        var storeReference: StoreReference?
        var installPath: URL
        var executablePath: URL
        var environmentID: UUID?
        var evidence: [GameDiscoveryEvidence]
        var penalties: [String]
    }

    private static func isInvalidated(
        _ candidate: GameDiscoveryCandidate,
        by scope: (root: URL, source: GameDiscoverySource?)
    ) -> Bool {
        if let source = scope.source {
            if source == .filesystem {
                return isWithin(candidate.installPath, root: scope.root)
            }
            // Steam libraryfolders can point at another volume, so the
            // manifest root is not necessarily an ancestor of the game.
            return candidate.sources.contains(source)
        }
        return isWithin(candidate.installPath, root: scope.root)
    }

    private static func isWithin(_ child: URL, root: URL) -> Bool {
        let childPath = child.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return childPath == rootPath || childPath.hasPrefix(rootPath + "/")
    }

    private static func mergeCandidates(_ values: [GameDiscoveryCandidate]) -> [GameDiscoveryCandidate] {
        var result: [String: GameDiscoveryCandidate] = [:]
        for candidate in values {
            let key = candidate.storeReference.map {
                "store:\($0.provider.rawValue.lowercased()):\($0.externalID.lowercased())"
            } ?? "path:\(candidate.installPath.standardizedFileURL.path.lowercased())"
            guard let existing = result[key] else {
                result[key] = candidate
                continue
            }
            if candidate.score > existing.score || (candidate.score == existing.score && candidate.source.priority < existing.source.priority) {
                result[key] = candidate
            }
        }
        return result.values.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private enum BorealEnvironmentDetector {
        static func detect(environment: GameDiscoveryEnvironment, fileManager: FileManager) -> [RawFinding] {
            let driveC = environment.prefixURL.appending(path: "drive_c", directoryHint: .isDirectory)
            let roots = ["Program Files", "Program Files (x86)", "GOG Games", "Games"].map {
                driveC.appending(path: $0, directoryHint: .isDirectory)
            }
            return roots.flatMap {
                FilesystemDetector.detect(
                    root: $0,
                    source: .borealEnvironment,
                    environmentID: environment.id,
                    fileManager: fileManager
                )
            }
        }
    }

    private enum SteamManifestDetector {
        static func detect(steamRoot: URL, fileManager: FileManager) -> [RawFinding] {
            let steamApps = steamRoot.appending(path: "steamapps", directoryHint: .isDirectory)
            guard fileManager.fileExists(atPath: steamApps.path) else { return [] }
            var libraryDirectories = [steamApps]
            let foldersURL = steamApps.appending(path: "libraryfolders.vdf")
            if let root = try? ValveKeyValueDecoder.decode(url: foldersURL),
               let folders = root.object("libraryfolders") {
                for value in folders.values {
                    guard let path = value.objectValue?.string("path"), !path.isEmpty else { continue }
                    let candidate = URL(fileURLWithPath: path).appending(path: "steamapps", directoryHint: .isDirectory)
                    if !libraryDirectories.contains(candidate) { libraryDirectories.append(candidate) }
                }
            }

            var findings: [RawFinding] = []
            for library in libraryDirectories {
                let manifests = (try? fileManager.contentsOfDirectory(at: library, includingPropertiesForKeys: nil)) ?? []
                for manifest in manifests where manifest.lastPathComponent.hasPrefix("appmanifest_") && manifest.pathExtension.caseInsensitiveCompare("acf") == .orderedSame {
                    guard let root = try? ValveKeyValueDecoder.decode(url: manifest),
                          let state = root.object("AppState"),
                          let appID = state.string("appid") ?? manifest.lastPathComponent.split(separator: "_").last.map { $0.dropLast(4) }.map(String.init),
                          let installDirectory = state.string("installdir"),
                          !installDirectory.isEmpty else { continue }
                    let installURL = library.appending(path: "common/\(installDirectory)", directoryHint: .isDirectory).standardizedFileURL
                    let commonRoot = library.appending(path: "common", directoryHint: .isDirectory).standardizedFileURL
                    guard isWithin(installURL, root: commonRoot),
                          installURL != commonRoot,
                          fileManager.fileExists(atPath: installURL.path) else { continue }
                    guard let executable = selectExecutable(
                        in: installURL,
                        name: state.string("name") ?? "Steam App \(appID)",
                        preferred: nil,
                        fileManager: fileManager
                    ) else { continue }
                    findings.append(manifestFinding(
                        source: .steamManifest,
                        name: state.string("name") ?? "Steam App \(appID)",
                        storeReference: StoreReference(provider: .steam, externalID: appID),
                        installPath: installURL,
                        executablePath: executable.url,
                        executableScore: executable.score,
                        environmentID: nil
                    ))
                }
            }
            return findings
        }
    }

    private enum GOGManifestDetector {
        static func detect(root: URL, environmentID: UUID?, fileManager: FileManager) -> [RawFinding] {
            guard fileManager.fileExists(atPath: root.path),
                  let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
            var findings: [RawFinding] = []
            for case let infoURL as URL in enumerator where infoURL.lastPathComponent.hasPrefix("goggame-") && infoURL.pathExtension.caseInsensitiveCompare("info") == .orderedSame {
                guard let data = try? Data(contentsOf: infoURL),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let externalID = string(json, keys: ["gameId", "rootGameId"]),
                      !externalID.isEmpty else { continue }
                let installURL = infoURL.deletingLastPathComponent().standardizedFileURL
                let name = string(json, keys: ["name", "title"]) ?? installURL.lastPathComponent
                let preferred = primaryTaskURL(json["playTasks"], installationURL: installURL, fileManager: fileManager)
                guard let executable = selectExecutable(in: installURL, name: name, preferred: preferred, fileManager: fileManager) else { continue }
                findings.append(manifestFinding(
                    source: .gogManifest,
                    name: name,
                    storeReference: StoreReference(provider: .gog, externalID: externalID),
                    installPath: installURL,
                    executablePath: executable.url,
                    executableScore: executable.score,
                    environmentID: environmentID
                ))
            }
            return findings
        }
    }

    private enum EpicManifestDetector {
        static func detect(
            root: URL,
            environmentID: UUID?,
            prefixURL: URL?,
            allowedInstallRoots: [URL],
            fileManager: FileManager
        ) -> [RawFinding] {
            guard fileManager.fileExists(atPath: root.path),
                  let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
            var findings: [RawFinding] = []
            for case let manifestURL as URL in enumerator where manifestURL.pathExtension.caseInsensitiveCompare("item") == .orderedSame {
                guard let json = jsonObject(at: manifestURL),
                      let externalID = string(json, keys: ["AppName", "app_name", "CatalogItemId", "CatalogNamespace"]),
                      let installURL = installationURL(
                          string(json, keys: ["InstallLocation", "install_location", "InstallPath", "install_path"]),
                          relativeTo: manifestURL.deletingLastPathComponent(),
                          prefixURL: prefixURL,
                          allowedRoots: allowedInstallRoots,
                          fileManager: fileManager
                      ) else { continue }
                let name = string(json, keys: ["DisplayName", "display_name", "AppTitle", "app_title"]) ?? installURL.lastPathComponent
                let preferred = string(json, keys: ["LaunchExecutable", "launch_executable", "executable"]).flatMap { launchPath in
                    childURL(launchPath, of: installURL, fileManager: fileManager)
                        ?? prefixURL.flatMap { prefix in
                            windowsURL(
                                launchPath,
                                prefixURL: prefix,
                                baseURL: prefix.appending(path: "drive_c", directoryHint: .isDirectory),
                                fileManager: fileManager
                            )
                        }
                }
                guard let executable = selectExecutable(in: installURL, name: name, preferred: preferred, fileManager: fileManager) else { continue }
                findings.append(manifestFinding(
                    source: .epicManifest,
                    name: name,
                    storeReference: StoreReference(provider: .epic, externalID: externalID),
                    installPath: installURL,
                    executablePath: executable.url,
                    executableScore: executable.score,
                    environmentID: environmentID
                ))
            }
            return findings
        }
    }

    private enum RegistryDetector {
        static func detect(environment: GameDiscoveryEnvironment, fileManager: FileManager) -> [RawFinding] {
            ["system.reg", "user.reg", "userdef.reg"].flatMap { fileName in
                detect(
                    registryURL: environment.prefixURL.appending(path: fileName),
                    environment: environment,
                    fileManager: fileManager
                )
            }
        }

        private static func detect(
            registryURL: URL,
            environment: GameDiscoveryEnvironment,
            fileManager: FileManager
        ) -> [RawFinding] {
            guard let text = try? String(contentsOf: registryURL, encoding: .utf8) else { return [] }
            var currentKey = ""
            var displayName: String?
            var installLocation: String?
            var displayIcon: String?
            var findings: [RawFinding] = []

            func flush() {
                guard currentKey.localizedCaseInsensitiveContains("currentversion\\uninstall"),
                      let name = displayName, !name.isEmpty else {
                    displayName = nil; installLocation = nil; displayIcon = nil
                    return
                }
                let preferred = displayIcon.flatMap {
                    windowsURL($0, prefixURL: environment.prefixURL, baseURL: environment.prefixURL, fileManager: fileManager)
                }
                let location = installLocation.flatMap {
                    windowsURL($0, prefixURL: environment.prefixURL, baseURL: environment.prefixURL, fileManager: fileManager)
                } ?? preferred?.deletingLastPathComponent()
                guard let location, fileManager.fileExists(atPath: location.path) else {
                    displayName = nil; installLocation = nil; displayIcon = nil
                    return
                }
                guard let executable = selectExecutable(in: location, name: name, preferred: preferred, fileManager: fileManager) else {
                    displayName = nil; installLocation = nil; displayIcon = nil
                    return
                }
                var evidence = [GameDiscoveryEvidence(points: 60, message: "Registry InstallLocation")]
                if preferred != nil { evidence.append(GameDiscoveryEvidence(points: 40, message: "Registry DisplayIcon")) }
                evidence += executableEvidence(executable.score)
                findings.append(RawFinding(
                    name: name,
                    source: .registry,
                    storeReference: nil,
                    installPath: location,
                    executablePath: executable.url,
                    environmentID: environment.id,
                    evidence: evidence,
                    penalties: executablePenalties(executable.url)
                ))
                displayName = nil; installLocation = nil; displayIcon = nil
            }

            for line in text.split(whereSeparator: \.isNewline).map(String.init) {
                if line.hasPrefix("[") {
                    flush()
                    currentKey = line
                } else if line.hasPrefix("\"DisplayName\"=") {
                    displayName = registryValue(line)
                } else if line.hasPrefix("\"InstallLocation\"=") {
                    installLocation = registryValue(line)
                } else if line.hasPrefix("\"DisplayIcon\"=") {
                    displayIcon = registryValue(line)
                }
            }
            flush()
            return findings
        }
    }

    private enum ShortcutDetector {
        static func detect(environment: GameDiscoveryEnvironment, fileManager: FileManager) -> [RawFinding] {
            let driveC = environment.prefixURL.appending(path: "drive_c", directoryHint: .isDirectory)
            let usersRoot = driveC.appending(path: "users", directoryHint: .isDirectory)
            var roots = [
                driveC.appending(path: "ProgramData/Microsoft/Windows/Start Menu", directoryHint: .isDirectory),
            ]
            if let users = try? fileManager.contentsOfDirectory(at: usersRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                roots += users.flatMap { user in
                    [
                        user.appending(path: "Desktop", directoryHint: .isDirectory),
                        user.appending(path: "AppData/Roaming/Microsoft/Windows/Start Menu", directoryHint: .isDirectory),
                    ]
                }
            }

            var findings: [RawFinding] = []
            for root in uniqueURLs(roots) {
                guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
                let isStartMenu = root.path.localizedCaseInsensitiveContains("start menu")
                for case let shortcut as URL in enumerator where shortcut.pathExtension.caseInsensitiveCompare("lnk") == .orderedSame {
                    guard let target = shortcutTarget(shortcut, fileManager: fileManager),
                          let executable = windowsURL(target, prefixURL: environment.prefixURL, baseURL: driveC, fileManager: fileManager),
                          fileManager.fileExists(atPath: executable.path),
                          ExecutableDiscovery.isEligibleExecutablePath(executable.lastPathComponent) else { continue }
                    let installURL = executable.deletingLastPathComponent()
                    let name = shortcut.deletingPathExtension().lastPathComponent
                    guard let ranked = selectExecutable(in: installURL, name: name, preferred: executable, fileManager: fileManager) else { continue }
                    var evidence = [GameDiscoveryEvidence(points: isStartMenu ? 50 : 30, message: isStartMenu ? "Start Menu shortcut" : "Desktop shortcut")]
                    evidence += executableEvidence(ranked.score)
                    findings.append(RawFinding(
                        name: name,
                        source: .shortcut,
                        storeReference: nil,
                        installPath: installURL,
                        executablePath: ranked.url,
                        environmentID: environment.id,
                        evidence: evidence,
                        penalties: executablePenalties(ranked.url)
                    ))
                }
            }
            return findings
        }
    }

    private enum FilesystemDetector {
        static func detect(
            root: URL,
            source: GameDiscoverySource = .filesystem,
            environmentID: UUID?,
            fileManager: FileManager
        ) -> [RawFinding] {
            guard fileManager.fileExists(atPath: root.path),
                  let values = try? root.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true else { return [] }
            let snapshot = ExecutableDiscovery.snapshot(at: root, fileManager: fileManager)
            let ranked = ExecutableDiscovery.rankedCandidates(
                before: ExecutableFilesystemSnapshot(rootURL: root, entries: []),
                after: snapshot,
                applicationName: root.lastPathComponent
            )
            return ranked.compactMap { candidate in
                guard candidate.score >= ExecutableDiscovery.minimumLaunchCandidateScore,
                      ExecutableDiscovery.isEligibleExecutablePath(candidate.relativePath) else { return nil }
                let installURL = gameRoot(for: candidate.url, under: root)
                let name = installURL == root ? candidate.url.deletingPathExtension().lastPathComponent : installURL.lastPathComponent
                var evidence = [GameDiscoveryEvidence(
                    points: source == .borealEnvironment ? 20 : 20,
                    message: source == .borealEnvironment ? "Executable inside a Boreal environment" : "Executable inside a configured game folder"
                )]
                evidence += executableEvidence(candidate.score)
                return RawFinding(
                    name: name,
                    source: source,
                    storeReference: nil,
                    installPath: installURL,
                    executablePath: candidate.url,
                    environmentID: environmentID,
                    evidence: evidence,
                    penalties: executablePenalties(candidate.url)
                )
            }
        }
    }

    private static func manifestFinding(
        source: GameDiscoverySource,
        name: String,
        storeReference: StoreReference,
        installPath: URL,
        executablePath: URL,
        executableScore: Int,
        environmentID: UUID?
    ) -> RawFinding {
        RawFinding(
            name: name,
            source: source,
            storeReference: storeReference,
            installPath: installPath,
            executablePath: executablePath,
            environmentID: environmentID,
            evidence: [GameDiscoveryEvidence(points: 100, message: "Store manifest")] + executableEvidence(executableScore),
            penalties: executablePenalties(executablePath)
        )
    }

    private static func executableEvidence(_ score: Int) -> [GameDiscoveryEvidence] {
        if score >= 80 { return [GameDiscoveryEvidence(points: 30, message: "Executable matches the game profile")] }
        if score >= 40 { return [GameDiscoveryEvidence(points: 20, message: "Executable is a plausible GUI game entry point")] }
        return []
    }

    private static func executablePenalties(_ url: URL) -> [String] {
        let lower = url.path.lowercased()
        var values: [String] = []
        if lower.contains("launcher") { values.append("launcher executable") }
        if lower.contains("updater") || lower.contains("update") { values.append("updater executable") }
        if lower.contains("setup") || lower.contains("installer") { values.append("installer executable") }
        if lower.contains("helper") || lower.contains("crash") { values.append("helper or crash executable") }
        if lower.contains("redistributable") || lower.contains("redist") || lower.contains("directx")
            || lower.contains("dotnet") || lower.contains("vcredist") {
            values.append("runtime or redistributable executable")
        }
        return values
    }

    private static func penaltyPoints(for penalties: [String]) -> Int {
        penalties.reduce(0) { total, penalty in
            let points: Int
            switch penalty {
            case "launcher executable": points = 20
            case "updater executable": points = 50
            case "installer executable": points = 100
            case "helper or crash executable": points = 80
            case "runtime or redistributable executable": points = 80
            default: points = 0
            }
            return total + points
        }
    }

    private static func deduplicate(_ findings: [RawFinding]) -> [GameDiscoveryCandidate] {
        var grouped: [String: [RawFinding]] = [:]
        for finding in findings {
            let key: String
            key = "path:\(pathKey(finding.installPath))"
            grouped[key, default: []].append(finding)
        }

        return grouped.values.compactMap { values in
            guard let best = values.sorted(by: rawFindingSort).first else { return nil }
            let allEvidence = values.flatMap(\.evidence)
            let uniqueEvidence = allEvidence.reduce(into: [String: GameDiscoveryEvidence]()) { result, item in
                if result[item.message] == nil || result[item.message]!.points < item.points { result[item.message] = item }
            }.values
            let allPenalties = Array(Set(values.flatMap(\.penalties))).sorted()
            let score = min(100, max(0, uniqueEvidence.reduce(0) { $0 + $1.points } - penaltyPoints(for: allPenalties)))
            let sources = values.map(\.source).sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                return lhs.rawValue < rhs.rawValue
            }.reduce(into: [GameDiscoverySource]()) { result, source in
                if !result.contains(source) { result.append(source) }
            }
            let installPath = values.first(where: { $0.source.priority == 0 })?.installPath ?? best.installPath
            let executable = values.sorted(by: rawFindingSort).first?.executablePath ?? best.executablePath
            let reference = values.compactMap(\.storeReference).first
            let environmentID = values.compactMap(\.environmentID).first
            let stableID = reference.map {
                "store:\($0.provider.rawValue.lowercased()):\($0.externalID.lowercased())"
            } ?? "path:\(pathKey(installPath))"
            return GameDiscoveryCandidate(
                id: stableID,
                name: values.first(where: { $0.source.priority == 0 })?.name ?? best.name,
                source: sources.first ?? best.source,
                sources: sources,
                storeReference: reference,
                installPath: installPath,
                executablePath: executable,
                environmentID: environmentID,
                score: score,
                reasons: uniqueEvidence.sorted { $0.points > $1.points }.map(\.message),
                penalties: allPenalties
            )
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func rawFindingSort(_ lhs: RawFinding, _ rhs: RawFinding) -> Bool {
        let leftScore = lhs.evidence.reduce(0) { $0 + $1.points }
        let rightScore = rhs.evidence.reduce(0) { $0 + $1.points }
        if leftScore != rightScore { return leftScore > rightScore }
        if lhs.source.priority != rhs.source.priority { return lhs.source.priority < rhs.source.priority }
        return lhs.executablePath.path.localizedStandardCompare(rhs.executablePath.path) == .orderedAscending
    }

    private static func steamRoots(in context: GameDiscoveryContext, fileManager: FileManager) -> [URL] {
        let defaultRoot = context.homeURL.appending(path: "Library/Application Support/Steam", directoryHint: .isDirectory)
        let configured = context.customRoots.filter { $0.lastPathComponent.localizedCaseInsensitiveContains("steam") }
        return uniqueURLs([defaultRoot] + configured + context.environments.flatMap { environment in
            [
                environment.prefixURL.appending(path: "drive_c/Program Files (x86)/Steam", directoryHint: .isDirectory),
                environment.prefixURL.appending(path: "drive_c/Program Files/Steam", directoryHint: .isDirectory),
            ]
        }).filter { fileManager.fileExists(atPath: $0.path) }
    }

    private static func shouldScan(
        root: URL,
        prefix: String,
        cache: inout GameDiscoveryCache,
        force: Bool,
        fileManager: FileManager
    ) -> Bool {
        let key = "\(prefix):\(pathKey(root))"
        let value = signature(for: root, fileManager: fileManager)
        let changed = force || cache.rootSignatures[key] != value
        if let value { cache.rootSignatures[key] = value }
        return changed
    }

    private static func signature(for root: URL, fileManager: FileManager) -> String? {
        guard fileManager.fileExists(atPath: root.path) else { return nil }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        var parts: [String] = []
        if let values = try? root.resourceValues(forKeys: keys) {
            parts.append("root|\(values.contentModificationDate?.timeIntervalSinceReferenceDate ?? -1)|\(values.fileSize ?? -1)")
        }
        let children = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
        for child in children.sorted(by: { $0.path < $1.path }).prefix(512) {
            let values = try? child.resourceValues(forKeys: keys)
            parts.append("\(child.lastPathComponent)|\(values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? -1)|\(values?.fileSize ?? -1)")
        }
        return parts.joined(separator: "\n")
    }

    private static func environmentID(for root: URL, in context: GameDiscoveryContext) -> UUID? {
        environment(for: root, in: context)?.id
    }

    private static func environment(for root: URL, in context: GameDiscoveryContext) -> GameDiscoveryEnvironment? {
        let path = root.standardizedFileURL.path
        return context.environments.first { environment in
            let prefix = environment.prefixURL.standardizedFileURL.path
            return path == prefix || path.hasPrefix(prefix + "/")
        }
    }

    private static func allowedManifestInstallRoots(in context: GameDiscoveryContext) -> [URL] {
        uniqueURLs([
            context.borealGamesRoot,
            context.homeURL.appending(path: "Games", directoryHint: .isDirectory),
            context.homeURL.appending(path: "GOG Games", directoryHint: .isDirectory),
            context.applicationSupportURL.appending(path: "Games", directoryHint: .isDirectory),
            context.applicationSupportURL.appending(path: "StoreLibraries", directoryHint: .isDirectory),
            context.applicationSupportURL.appending(path: "Accounts", directoryHint: .isDirectory),
        ] + context.customRoots + context.environments.map(\.prefixURL))
    }

    private static func uniqueURLs(_ values: [URL]) -> [URL] {
        var seen = Set<String>()
        return values.map(\.standardizedFileURL).filter { seen.insert(pathKey($0)).inserted }
    }

    private static func pathKey(_ url: URL) -> String { url.standardizedFileURL.path.lowercased() }

    private static func gameRoot(for executable: URL, under root: URL) -> URL {
        let normalizedRoot = root.standardizedFileURL
        let path = executable.standardizedFileURL.path
        let prefix = normalizedRoot.path.hasSuffix("/") ? normalizedRoot.path : normalizedRoot.path + "/"
        guard path.hasPrefix(prefix) else { return executable.deletingLastPathComponent() }
        let relative = String(path.dropFirst(prefix.count)).split(separator: "/")
        guard let first = relative.first, relative.count > 1 else { return normalizedRoot }
        return normalizedRoot.appending(path: String(first), directoryHint: .isDirectory).standardizedFileURL
    }

    private static func selectExecutable(
        in installURL: URL,
        name: String,
        preferred: URL?,
        fileManager: FileManager
    ) -> (url: URL, score: Int)? {
        if let preferred,
           preferred.pathExtension.caseInsensitiveCompare("exe") == .orderedSame,
           fileManager.fileExists(atPath: preferred.path),
           ExecutableDiscovery.isEligibleExecutablePath(preferred.lastPathComponent) {
            let snapshot = ExecutableDiscovery.snapshot(at: installURL, fileManager: fileManager)
            let score = ExecutableDiscovery.rankedCandidates(
                before: ExecutableFilesystemSnapshot(rootURL: installURL, entries: []),
                after: snapshot,
                applicationName: name
            ).first(where: { $0.url.standardizedFileURL == preferred.standardizedFileURL })?.score ?? 40
            return (preferred.standardizedFileURL, score)
        }
        let snapshot = ExecutableDiscovery.snapshot(at: installURL, fileManager: fileManager)
        return ExecutableDiscovery.rankedCandidates(
            before: ExecutableFilesystemSnapshot(rootURL: installURL, entries: []),
            after: snapshot,
            applicationName: name
        ).first(where: { $0.score >= ExecutableDiscovery.minimumLaunchCandidateScore && fileManager.fileExists(atPath: $0.url.path) })
            .map { ($0.url.standardizedFileURL, $0.score) }
    }

    private static func jsonObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func string(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String { return value }
            if let value = dictionary[key] as? NSNumber { return value.stringValue }
        }
        let normalized = Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key.lowercased(), $0.value) })
        for key in keys where normalized[key.lowercased()] != nil {
            if let value = normalized[key.lowercased()] as? String { return value }
            if let value = normalized[key.lowercased()] as? NSNumber { return value.stringValue }
        }
        return nil
    }

    private static func primaryTaskURL(_ value: Any?, installationURL: URL, fileManager: FileManager) -> URL? {
        guard let tasks = value as? [[String: Any]] else { return nil }
        let task = tasks.first(where: { ($0["isPrimary"] as? Bool) == true && ($0["type"] as? String) != "URLTask" })
            ?? tasks.first(where: { ($0["type"] as? String) != "URLTask" })
        guard let path = task?["path"] as? String else { return nil }
        return childURL(path, of: installationURL, fileManager: fileManager)
    }

    private static func installationURL(
        _ value: String?,
        relativeTo base: URL,
        prefixURL: URL? = nil,
        allowedRoots: [URL] = [],
        fileManager: FileManager
    ) -> URL? {
        guard let value else { return nil }
        let candidate = childURL(value, of: base, fileManager: fileManager)
            ?? prefixURL.flatMap {
                windowsURL(
                    value,
                    prefixURL: $0,
                    baseURL: $0.appending(path: "drive_c", directoryHint: .isDirectory),
                    fileManager: fileManager
                )
            }
            ?? URL(fileURLWithPath: value).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              allowedRoots.isEmpty || allowedRoots.contains(where: { isWithin(candidate, root: $0) }) else { return nil }
        return candidate
    }

    private static func childURL(_ value: String, of base: URL, fileManager: FileManager) -> URL? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"")))
        if cleaned.isEmpty { return nil }
        let normalized = cleaned.replacingOccurrences(of: "\\", with: "/")
        let candidate: URL
        if normalized.range(of: "^[A-Za-z]:/", options: .regularExpression) != nil {
            candidate = URL(fileURLWithPath: normalized)
        } else if normalized.hasPrefix("/") {
            candidate = URL(fileURLWithPath: normalized)
        } else {
            candidate = base.appending(path: normalized)
        }
        let result = candidate.standardizedFileURL
        let basePath = base.standardizedFileURL.path
        guard result.path == basePath || result.path.hasPrefix(basePath + "/") || fileManager.fileExists(atPath: result.path) else { return nil }
        return result
    }

    private static func windowsURL(_ value: String, prefixURL: URL, baseURL: URL, fileManager: FileManager) -> URL? {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"")))
        if let comma = cleaned.firstIndex(of: ",") { cleaned = String(cleaned[..<comma]) }
        cleaned = cleaned.replacingOccurrences(of: "\\\\", with: "\\")
        let normalized = cleaned.replacingOccurrences(of: "\\", with: "/")
        if normalized.range(of: "^[A-Za-z]:/", options: .regularExpression) != nil {
            let suffix = String(normalized.dropFirst(3))
            let candidate = prefixURL.appending(path: "drive_c/\(suffix)").standardizedFileURL
            return fileManager.fileExists(atPath: candidate.path) ? candidate : nil
        }
        let candidate = URL(fileURLWithPath: normalized.hasPrefix("/") ? normalized : baseURL.appending(path: normalized).path).standardizedFileURL
        return fileManager.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private static func registryValue(_ line: String) -> String? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        var value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("\"") && value.hasSuffix("\"") else { return nil }
        value.removeFirst(); value.removeLast()
        return value.replacingOccurrences(of: "\\\\", with: "\\").replacingOccurrences(of: "\\\"", with: "\"")
    }

    private static func shortcutTarget(_ url: URL, fileManager: FileManager) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        var strings = [String(decoding: data, as: UTF8.self)]
        if let utf16 = String(data: data, encoding: .utf16LittleEndian) { strings.append(utf16) }
        let pattern = #"(?i)[a-z]:\\[^\0\r\n\"']{1,240}\.exe"#
        let regex = try? NSRegularExpression(pattern: pattern)
        for string in strings {
            let range = NSRange(string.startIndex..<string.endIndex, in: string)
            if let match = regex?.firstMatch(in: string, range: range),
               let valueRange = Range(match.range, in: string) {
                return String(string[valueRange])
            }
        }
        return nil
    }
}
