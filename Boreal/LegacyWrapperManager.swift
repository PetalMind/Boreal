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
            "The dgVoodoo2 component does not support the game’s \(architecture) architecture."
        case .unsupportedAPI(let api):
            "The dgVoodoo2 component does not support \(api.displayName)."
        case .wrapperLibraryMissing(let name):
            "The dgVoodoo2 component is missing \(name).dll."
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

    func activate(
        _ wrapper: LegacyGraphicsWrapper,
        api: LegacyGraphicsAPI,
        gameExecutable: URL,
        environment: ManagedBorealEnvironment,
        runtime: InstalledRuntime
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
        guard component.supportedAPIs.contains(api) else {
            throw GraphicsCompatibilityError.unsupportedAPI(api)
        }

        let source = componentRoot
            .appending(path: architecture, directoryHint: .isDirectory)
            .appending(path: "\(api.libraryName).dll")
        guard fileManager.fileExists(atPath: source.path) else {
            throw GraphicsCompatibilityError.wrapperLibraryMissing(api.libraryName)
        }
        let destination = gameDirectory.appending(path: "\(api.libraryName).dll")
        let previous = try installationSnapshot(in: gameDirectory)
        let previouslyManaged = previous?.files.contains { $0.url.standardizedFileURL == destination.standardizedFileURL } == true
        guard !fileManager.fileExists(atPath: destination.path) || previouslyManaged else {
            throw GraphicsCompatibilityError.foreignWrapperDetected(destination)
        }

        let backupRoot = gameDirectory.appending(path: ".boreal-legacy-wrapper-backups", directoryHint: .isDirectory)
        let manifestURL = manifestURL(in: gameDirectory)
        do {
            try reset(gameDirectory: gameDirectory)
            try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: destination)
            let installed = InstalledFile(destination: destination, backup: nil, installedSHA256: try sha256(of: destination))
            let manifest = InstallationManifest(wrapper: wrapper, componentVersion: component.version, files: [installed])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
            return LegacyWrapperActivation(
                wrapper: wrapper,
                dllOverrides: [DLLOverride(library: api.libraryName, mode: .nativeThenBuiltin)],
                files: [GraphicsInjectedFile(url: destination, owner: wrapper.rawValue)]
            )
        } catch {
            if fileManager.fileExists(atPath: destination.path) { try? fileManager.removeItem(at: destination) }
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
        guard wrapper == .dgVoodoo2 else { return nil }
        return [
            runtime.rootURL.appending(path: "GraphicsComponents/dgVoodoo2", directoryHint: .isDirectory),
            runtime.rootURL.appending(path: "Support/Graphics/dgVoodoo2", directoryHint: .isDirectory)
        ].first { fileManager.fileExists(atPath: $0.path) }
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
