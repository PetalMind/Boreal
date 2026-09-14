import CryptoKit
import Foundation

nonisolated struct GraphicsInjectedFile: Sendable, Hashable {
    let url: URL
    let owner: String
}

nonisolated struct LegacyWrapperActivation: Sendable, Hashable {
    let wrapper: LegacyGraphicsWrapper
    let dllOverrides: [DLLOverride]
    let files: [GraphicsInjectedFile]
}

nonisolated enum GraphicsCompatibilityError: LocalizedError, Sendable {
    case componentPackageMissing(LegacyGraphicsWrapper)
    case invalidComponentManifest(String)
    case unsupportedArchitecture(String)
    case unsupportedAPI(LegacyGraphicsAPI)
    case wrapperLibraryMissing(String)
    case foreignWrapperDetected(URL)
    case managedFileModified(URL)
    case unsafeManifestPath(URL)

    var errorDescription: String? {
        switch self {
        case .componentPackageMissing(let wrapper):
            "The selected runtime does not contain the \(wrapper.displayName) component."
        case .invalidComponentManifest(let reason):
            "The legacy graphics component manifest is invalid: \(reason)"
        case .unsupportedArchitecture(let architecture):
            "The selected legacy graphics component does not support the game’s \(architecture) architecture."
        case .unsupportedAPI(let api):
            "The selected legacy graphics component does not support \(api.displayName)."
        case .wrapperLibraryMissing(let name):
            "The selected legacy graphics component is missing \(name)."
        case .foreignWrapperDetected(let url):
            "The game already contains a custom wrapper at \(url.path). Boreal will not overwrite it."
        case .managedFileModified(let url):
            "A Boreal-managed wrapper file was modified outside Boreal at \(url.path). It was left untouched."
        case .unsafeManifestPath(let url):
            "The wrapper manifest refers to a file outside the game directory: \(url.path)"
        }
    }
}

nonisolated struct LegacyWrapperComponentManifest: Codable, Sendable, Hashable {
    let id: String
    let version: String
    let architectures: [String]
    let supportedAPIs: [LegacyGraphicsAPI]
    /// Optional list shared by every selected API. Dd7to9 uses this list for
    /// ddraw.dll, dxwrapper.dll and dxwrapper.ini. Older manifests without a
    /// list fall back to the selected API DLL name.
    let files: [String]?
    /// Maps a legacy API to the DLL that should be copied for that API. This
    /// is needed by dgVoodoo2 because it exposes separate DDraw, D3D8 and
    /// D3D9 entry points rather than one wrapper DLL for every API.
    let filesByAPI: [String: [String]]?
    /// Some packages expose a different API set per PE architecture. The
    /// standard dgVoodoo2 package is x86-capable for DDraw/D3D8/D3D9 but its
    /// x64 folder contains D3D9 only.
    let supportedAPIsByArchitecture: [String: [String]]?
    let sourceRepository: String?
    let sha256: String?
    let compressedSize: Int64?

    init(
        id: String,
        version: String,
        architectures: [String],
        supportedAPIs: [LegacyGraphicsAPI],
        files: [String]? = nil,
        filesByAPI: [String: [String]]? = nil,
        supportedAPIsByArchitecture: [String: [String]]? = nil,
        sourceRepository: String? = nil,
        sha256: String? = nil,
        compressedSize: Int64? = nil
    ) {
        self.id = id
        self.version = version
        self.architectures = architectures
        self.supportedAPIs = supportedAPIs
        self.files = files
        self.filesByAPI = filesByAPI
        self.supportedAPIsByArchitecture = supportedAPIsByArchitecture
        self.sourceRepository = sourceRepository
        self.sha256 = sha256
        self.compressedSize = compressedSize
    }
}

/// Installs one explicitly selected legacy API wrapper beside the game's EXE.
/// Its hidden manifest is the ownership boundary: untracked DLLs are foreign
/// and are never overwritten or removed.
nonisolated struct LegacyWrapperManager: Sendable {
    private struct InstalledFile: Codable, Sendable, Hashable {
        let destination: URL
        let backup: URL?
        let installedSHA256: String
    }

    private struct InstallationManifest: Codable, Sendable, Hashable {
        let wrapper: LegacyGraphicsWrapper
        let componentVersion: String
        let files: [InstalledFile]
    }

    private struct InstallationSnapshot {
        let manifestData: Data
        let files: [(url: URL, data: Data)]
    }

    private var fileManager: FileManager { .default }

    /// Optional wrapper packages live beside, rather than inside, immutable
    /// Wine runtime snapshots. This keeps a wrapper update independent from
    /// the runtime that happens to consume it.
    static func componentStorageURL(
        for wrapper: LegacyGraphicsWrapper,
        version: String,
        runtime: InstalledRuntime
    ) -> URL {
        runtime.rootURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Components/LegacyWrappers/\(wrapper.componentDirectoryName)/\(version)", directoryHint: .isDirectory)
    }

    func isAvailable(_ wrapper: LegacyGraphicsWrapper, in runtime: InstalledRuntime) -> Bool {
        guard wrapper != .none,
              let root = componentRoot(for: wrapper, runtime: runtime),
              let manifest = try? loadComponentManifest(at: root, expectedWrapper: wrapper),
              !manifest.architectures.isEmpty,
              !manifest.supportedAPIs.isEmpty else { return false }
        return manifest.architectures.contains { architecture in
            supportedAPIs(from: manifest, architecture: architecture).contains { api in
                guard let files = try? filesToInstall(from: manifest, api: api) else { return false }
                return files.allSatisfy {
                    fileManager.isReadableFile(
                        atPath: root.appending(path: "\(architecture)/\($0)").path
                    )
                }
            }
        }
    }

    func activate(
        _ wrapper: LegacyGraphicsWrapper,
        api: LegacyGraphicsAPI,
        gameExecutable: URL,
        environment: ManagedBorealEnvironment,
        runtime: InstalledRuntime,
        settings: [String: String] = [:]
    ) throws -> LegacyWrapperActivation {
        let gameDirectory = gameExecutable.deletingLastPathComponent().standardizedFileURL
        guard wrapper != .none else {
            try reset(gameDirectory: gameDirectory)
            return LegacyWrapperActivation(wrapper: .none, dllOverrides: [], files: [])
        }

        guard let componentRoot = componentRoot(for: wrapper, runtime: runtime) else {
            throw GraphicsCompatibilityError.componentPackageMissing(wrapper)
        }
        let component = try loadComponentManifest(at: componentRoot, expectedWrapper: wrapper)
        let architecture = resolvedArchitecture(for: gameExecutable, environment: environment)
        guard component.architectures.contains(architecture) else {
            throw GraphicsCompatibilityError.unsupportedArchitecture(architecture)
        }
        guard supportedAPIs(from: component, architecture: architecture).contains(api) else {
            throw GraphicsCompatibilityError.unsupportedAPI(api)
        }

        let fileNames = try filesToInstall(from: component, api: api)
        let sources = fileNames.map {
            componentRoot
                .appending(path: architecture, directoryHint: .isDirectory)
                .appending(path: $0)
        }
        for (fileName, source) in zip(fileNames, sources) where !fileManager.fileExists(atPath: source.path) {
            throw GraphicsCompatibilityError.wrapperLibraryMissing(fileName)
        }
        let dllDestinations = fileNames.map { gameDirectory.appending(path: $0) }
        let dgVoodooConfiguration = try dgVoodooConfiguration(
            for: wrapper,
            settings: settings
        )
        let destinations = dllDestinations + (dgVoodooConfiguration == nil
            ? []
            : [gameDirectory.appending(path: "dgVoodoo.conf")])
        let previous = try installationSnapshot(in: gameDirectory)
        let previouslyManaged = Set(previous?.files.map { $0.url.standardizedFileURL } ?? [])
        for destination in destinations {
            guard !fileManager.fileExists(atPath: destination.path) || previouslyManaged.contains(destination.standardizedFileURL) else {
                throw GraphicsCompatibilityError.foreignWrapperDetected(destination)
            }
        }

        let backupRoot = gameDirectory.appending(path: ".boreal-legacy-wrapper-backups", directoryHint: .isDirectory)
        let manifestURL = manifestURL(in: gameDirectory)
        do {
            try reset(gameDirectory: gameDirectory)
            try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
            var installed: [InstalledFile] = []
            for (index, destination) in destinations.enumerated() {
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if index < sources.count {
                    try fileManager.copyItem(at: sources[index], to: destination)
                    if wrapper == .dd7to9, destination.lastPathComponent.caseInsensitiveCompare("dxwrapper.ini") == .orderedSame {
                        try configureDd7to9(in: destination, settings: settings)
                    }
                } else if let dgVoodooConfiguration {
                    try dgVoodooConfiguration.write(to: destination, options: .atomic)
                }
                installed.append(InstalledFile(destination: destination, backup: nil, installedSHA256: try sha256(of: destination)))
            }
            let manifest = InstallationManifest(wrapper: wrapper, componentVersion: component.version, files: installed)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
            return LegacyWrapperActivation(
                wrapper: wrapper,
                dllOverrides: [DLLOverride(library: api.libraryName, mode: .nativeThenBuiltin)],
                files: destinations.map { GraphicsInjectedFile(url: $0, owner: wrapper.rawValue) }
            )
        } catch {
            for destination in destinations where fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            try? fileManager.removeItem(at: manifestURL)
            try? removeDirectoryIfEmpty(backupRoot)
            if let previous { try? restore(previous, in: gameDirectory) }
            throw error
        }
    }

    func reset(gameExecutable: URL) throws {
        try reset(gameDirectory: gameExecutable.deletingLastPathComponent().standardizedFileURL)
    }

    private func reset(gameDirectory: URL) throws {
        let url = manifestURL(in: gameDirectory)
        guard fileManager.fileExists(atPath: url.path) else { return }
        let manifest = try JSONDecoder().decode(InstallationManifest.self, from: Data(contentsOf: url))
        for file in manifest.files.reversed() {
            let destination = file.destination.standardizedFileURL
            guard destination.deletingLastPathComponent() == gameDirectory else {
                throw GraphicsCompatibilityError.unsafeManifestPath(destination)
            }
            if fileManager.fileExists(atPath: destination.path) {
                guard try sha256(of: destination) == file.installedSHA256 else {
                    throw GraphicsCompatibilityError.managedFileModified(destination)
                }
                try fileManager.removeItem(at: destination)
            }
            if let backup = file.backup, fileManager.fileExists(atPath: backup.path) {
                try fileManager.moveItem(at: backup, to: destination)
            }
        }
        try fileManager.removeItem(at: url)
        try? removeDirectoryIfEmpty(gameDirectory.appending(path: ".boreal-legacy-wrapper-backups", directoryHint: .isDirectory))
    }

    private func componentRoot(for wrapper: LegacyGraphicsWrapper, runtime: InstalledRuntime) -> URL? {
        guard wrapper != .none else { return nil }
        let embedded = [
            runtime.rootURL.appending(path: "GraphicsComponents/\(wrapper.componentDirectoryName)", directoryHint: .isDirectory),
            runtime.rootURL.appending(path: "Support/Graphics/\(wrapper.componentDirectoryName)", directoryHint: .isDirectory)
        ]
        let applicationSupport = runtime.rootURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sharedRoots = [
            applicationSupport.appending(path: "Components/LegacyWrappers/\(wrapper.componentDirectoryName)", directoryHint: .isDirectory),
            applicationSupport.appending(path: "Components/\(wrapper.componentDirectoryName)", directoryHint: .isDirectory)
        ]
        let versioned = sharedRoots.flatMap { root -> [URL] in
            guard let children = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
            return children
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
        }
        return (embedded + versioned).first {
            fileManager.fileExists(atPath: $0.appending(path: "manifest.json").path)
        }
    }

    private func loadComponentManifest(at root: URL, expectedWrapper: LegacyGraphicsWrapper) throws -> LegacyWrapperComponentManifest {
        let url = root.appending(path: "manifest.json")
        guard fileManager.fileExists(atPath: url.path) else {
            throw GraphicsCompatibilityError.invalidComponentManifest("manifest.json is missing")
        }
        let manifest = try JSONDecoder().decode(LegacyWrapperComponentManifest.self, from: Data(contentsOf: url))
        guard manifest.id.lowercased() == expectedWrapper.rawValue.lowercased() else {
            throw GraphicsCompatibilityError.invalidComponentManifest("component id does not match \(expectedWrapper.rawValue)")
        }
        return manifest
    }

    private func filesToInstall(
        from manifest: LegacyWrapperComponentManifest,
        api: LegacyGraphicsAPI
    ) throws -> [String] {
        let values = manifest.filesByAPI?[api.rawValue]
            ?? manifest.files
            ?? ["\(api.libraryName).dll"]
        guard !values.isEmpty,
              values.allSatisfy({ value in
                  !value.isEmpty
                      && value == URL(fileURLWithPath: value).lastPathComponent
                      && !value.hasPrefix(".")
                      && !value.contains("..")
                      && !value.contains("\\")
              }) else {
            throw GraphicsCompatibilityError.invalidComponentManifest("files contains an unsafe path")
        }
        return values
    }

    private func supportedAPIs(
        from manifest: LegacyWrapperComponentManifest,
        architecture: String
    ) -> [LegacyGraphicsAPI] {
        guard let values = manifest.supportedAPIsByArchitecture?[architecture] else {
            return manifest.supportedAPIs
        }
        return values.compactMap(LegacyGraphicsAPI.init(rawValue:))
    }

    private func configureDd7to9(in url: URL, settings: [String: String]) throws {
        guard var contents = try? String(contentsOf: url, encoding: .utf8) else {
            throw GraphicsCompatibilityError.invalidComponentManifest("dxwrapper.ini is not a UTF-8 text file")
        }
        var foundDd7to9 = false
        var remainingSettings = Set(settings.keys.map { $0.lowercased() })
        var lines = contents.components(separatedBy: .newlines)
        for index in lines.indices {
            let line = lines[index]
            guard let equal = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equal]).trimmingCharacters(in: .whitespacesAndNewlines)
            if key.caseInsensitiveCompare("Dd7to9") == .orderedSame {
                lines[index] = "Dd7to9 = 1"
                foundDd7to9 = true
                continue
            }
            guard let setting = settings.first(where: {
                $0.key.caseInsensitiveCompare(key) == .orderedSame
            }) else { continue }
            lines[index] = "\(key) = \(setting.value)"
            remainingSettings.remove(key.lowercased())
        }
        guard foundDd7to9 else {
            throw GraphicsCompatibilityError.invalidComponentManifest("dxwrapper.ini does not expose the Dd7to9 option")
        }
        guard remainingSettings.isEmpty else {
            let missing = remainingSettings.sorted().joined(separator: ", ")
            throw GraphicsCompatibilityError.invalidComponentManifest(
                "dxwrapper.ini does not expose the requested options: \(missing)"
            )
        }
        contents = lines.joined(separator: "\n")
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func dgVoodooConfiguration(
        for wrapper: LegacyGraphicsWrapper,
        settings: [String: String]
    ) throws -> Data? {
        guard wrapper == .dgVoodoo2, !settings.isEmpty else { return nil }
        let allowedOutputAPIs = Set([
            "d3d11warp",
            "d3d11_fl10_0",
            "d3d11_fl10_1",
            "d3d11_fl11_0",
            "d3d12_fl11_0",
            "d3d12_fl12_0",
            "bestavailable"
        ])
        let outputAPI = settings.first { $0.key.caseInsensitiveCompare("OutputAPI") == .orderedSame }?.value
            ?? "bestavailable"
        guard allowedOutputAPIs.contains(outputAPI.lowercased()) else {
            throw GraphicsCompatibilityError.invalidComponentManifest(
                "dgVoodoo2 requested an unsupported OutputAPI: \(outputAPI)"
            )
        }
        let unknownKeys = settings.keys.filter {
            $0.caseInsensitiveCompare("OutputAPI") != .orderedSame
        }
        guard unknownKeys.isEmpty else {
            throw GraphicsCompatibilityError.invalidComponentManifest(
                "dgVoodoo2 does not support the requested settings: \(unknownKeys.sorted().joined(separator: ", "))"
            )
        }
        return Data("""
        ; Boreal-managed dgVoodoo2 configuration. It is removed with the
        ; wrapper activation manifest when the compatibility fix is disabled.
        Version = 0x287

        [General]
        OutputAPI = \(outputAPI)
        Adapters = all
        FullScreenMode = false
        KeepWindowAspectRatio = true
        CaptureMouse = true
        """.utf8)
    }

    private func resolvedArchitecture(for executable: URL, environment: ManagedBorealEnvironment) -> String {
        switch WindowsExecutableArchitecture.inspect(executable) {
        case .x86: "x86"
        case .x86_64: "x64"
        case .unknown: environment.configuration.architecture == WinePrefixArchitecture.win32.rawValue ? "x86" : "x64"
        }
    }

    private func manifestURL(in gameDirectory: URL) -> URL {
        gameDirectory.appending(path: ".boreal-legacy-wrapper.json")
    }

    private func installationSnapshot(in gameDirectory: URL) throws -> InstallationSnapshot? {
        let url = manifestURL(in: gameDirectory)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(InstallationManifest.self, from: data)
        let files = try manifest.files.compactMap { file -> (URL, Data)? in
            let destination = file.destination.standardizedFileURL
            guard destination.deletingLastPathComponent() == gameDirectory else {
                throw GraphicsCompatibilityError.unsafeManifestPath(destination)
            }
            guard fileManager.fileExists(atPath: destination.path) else { return nil }
            guard try sha256(of: destination) == file.installedSHA256 else {
                throw GraphicsCompatibilityError.managedFileModified(destination)
            }
            return (destination, try Data(contentsOf: destination))
        }
        return InstallationSnapshot(manifestData: data, files: files)
    }

    private func restore(_ snapshot: InstallationSnapshot, in gameDirectory: URL) throws {
        for file in snapshot.files {
            try file.data.write(to: file.url, options: .atomic)
        }
        try snapshot.manifestData.write(to: manifestURL(in: gameDirectory), options: .atomic)
    }

    private func sha256(of url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private func removeDirectoryIfEmpty(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path),
              try fileManager.contentsOfDirectory(atPath: url.path).isEmpty else { return }
        try fileManager.removeItem(at: url)
    }
}
