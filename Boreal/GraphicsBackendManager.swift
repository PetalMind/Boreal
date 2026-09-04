import Foundation

nonisolated struct GraphicsBackendActivation: Sendable, Equatable {
    let backend: WineGraphicsBackend
    let dllOverrides: [String]
}

nonisolated enum GraphicsBackendManagerError: LocalizedError, Sendable {
    case componentPackageMissing(WineGraphicsBackend)
    case componentPackageEmpty(WineGraphicsBackend)

    var errorDescription: String? {
        switch self {
        case .componentPackageMissing(let backend):
            "The selected runtime advertises \(backend.displayName), but its graphics component package is missing."
        case .componentPackageEmpty(let backend):
            "The \(backend.displayName) component package does not contain supported Direct3D libraries."
        }
    }
}

/// Owns the prefix files used by optional renderers. Registry overrides are
/// applied by EnvironmentManager through the selected runtime's `wine reg`.
/// Every activation starts by restoring the previous Boreal-managed files.
nonisolated struct GraphicsBackendManager: Sendable {
    private struct InstalledFile: Codable {
        let destination: URL
        let backup: URL?
    }

    private struct InstallationManifest: Codable {
        let backend: WineGraphicsBackend
        let files: [InstalledFile]
    }

    private var fileManager: FileManager { .default }
    private let supportedDLLs = Set(["d3d9.dll", "d3d10.dll", "d3d10_1.dll", "d3d10core.dll", "d3d11.dll", "d3d12.dll", "dxgi.dll"])

    func resolve(
        _ requested: WineGraphicsBackend,
        graphicsAPI: GraphicsAPI = .automatic,
        runtime: InstalledRuntime
    ) -> WineGraphicsBackend {
        guard requested == .automatic else { return requested }
        return RendererPolicy.preferredBackend(for: graphicsAPI, runtime: runtime)
    }

    func activate(
        _ requested: WineGraphicsBackend,
        in environment: ManagedBorealEnvironment,
        runtime: InstalledRuntime
    ) throws -> GraphicsBackendActivation {
        try reset(environment)
        let backend = resolve(requested, graphicsAPI: environment.configuration.graphicsAPI, runtime: runtime)
        guard backend == .dxmt || backend == .dxvk else {
            return GraphicsBackendActivation(backend: backend, dllOverrides: [])
        }

        guard supports(backend, runtime: runtime), let componentRoot = componentRoot(for: backend, runtime: runtime) else {
            throw GraphicsBackendManagerError.componentPackageMissing(backend)
        }
        let candidates = try componentFiles(in: componentRoot, environment: environment)
        guard !candidates.isEmpty else { throw GraphicsBackendManagerError.componentPackageEmpty(backend) }

        let backupRoot = environment.rootURL.appending(path: ".graphics-backup", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        var installed: [InstalledFile] = []
        do {
            for (source, destination) in candidates {
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                let backup: URL?
                if fileManager.fileExists(atPath: destination.path) {
                    let saved = backupRoot.appending(path: "\(installed.count)-\(destination.lastPathComponent)")
                    try fileManager.moveItem(at: destination, to: saved)
                    backup = saved
                } else {
                    backup = nil
                }
                try fileManager.copyItem(at: source, to: destination)
                installed.append(InstalledFile(destination: destination, backup: backup))
            }
            let manifest = InstallationManifest(backend: backend, files: installed)
            try JSONEncoder().encode(manifest).write(to: manifestURL(environment), options: .atomic)
        } catch {
            try? restore(installed.reversed())
            try? fileManager.removeItem(at: backupRoot)
            throw error
        }

        let overrides = Array(Set(installed.map { $0.destination.deletingPathExtension().lastPathComponent })).sorted()
        return GraphicsBackendActivation(backend: backend, dllOverrides: overrides)
    }

    func reset(_ environment: ManagedBorealEnvironment) throws {
        let url = manifestURL(environment)
        guard fileManager.fileExists(atPath: url.path) else { return }
        let manifest = try JSONDecoder().decode(InstallationManifest.self, from: Data(contentsOf: url))
        try restore(manifest.files.reversed())
        try? fileManager.removeItem(at: url)
        try? fileManager.removeItem(at: environment.rootURL.appending(path: ".graphics-backup"))
    }

    func prefixDidMove(
        in environment: ManagedBorealEnvironment,
        from oldPrefix: URL
    ) throws {
        let url = manifestURL(environment)
        guard fileManager.fileExists(atPath: url.path) else { return }
        let manifest = try JSONDecoder().decode(InstallationManifest.self, from: Data(contentsOf: url))
        let oldPath = oldPrefix.standardizedFileURL.path + "/"
        let files = try manifest.files.map { file -> InstalledFile in
            let destinationPath = file.destination.standardizedFileURL.path
            guard destinationPath.hasPrefix(oldPath) else { throw CocoaError(.fileReadCorruptFile) }
            let relativePath = String(destinationPath.dropFirst(oldPath.count))
            return InstalledFile(
                destination: environment.prefixURL.appending(path: relativePath),
                backup: file.backup
            )
        }
        try JSONEncoder().encode(InstallationManifest(backend: manifest.backend, files: files))
            .write(to: url, options: .atomic)
    }

    private func restore<S: Sequence>(_ files: S) throws where S.Element == InstalledFile {
        for file in files {
            if fileManager.fileExists(atPath: file.destination.path) {
                try fileManager.removeItem(at: file.destination)
            }
            if let backup = file.backup, fileManager.fileExists(atPath: backup.path) {
                try fileManager.moveItem(at: backup, to: file.destination)
            }
        }
    }

    private func supports(_ backend: WineGraphicsBackend, runtime: InstalledRuntime) -> Bool {
        switch backend {
        case .dxmt: runtime.features?.dxmt == true
        case .dxvk: runtime.features?.dxvk == true
        default: true
        }
    }

    private func componentRoot(for backend: WineGraphicsBackend, runtime: InstalledRuntime) -> URL? {
        let folder = backend == .dxmt ? "DXMT" : "DXVK"
        return [
            runtime.rootURL.appending(path: "GraphicsComponents/\(folder)", directoryHint: .isDirectory),
            runtime.rootURL.appending(path: "Support/Graphics/\(folder)", directoryHint: .isDirectory)
        ].first { fileManager.fileExists(atPath: $0.path) }
    }

    private func componentFiles(
        in root: URL,
        environment: ManagedBorealEnvironment
    ) throws -> [(URL, URL)] {
        let is64Bit = environment.configuration.architecture == WinePrefixArchitecture.win64.rawValue
        let layouts: [(String, String)] = is64Bit
            ? [("x64", "system32"), ("x32", "syswow64")]
            : [("x32", "system32")]
        var result: [(URL, URL)] = []
        for (sourceFolder, windowsFolder) in layouts {
            let sourceRoot = root.appending(path: sourceFolder, directoryHint: .isDirectory)
            guard fileManager.fileExists(atPath: sourceRoot.path) else { continue }
            let files = try fileManager.contentsOfDirectory(at: sourceRoot, includingPropertiesForKeys: nil)
            for source in files where supportedDLLs.contains(source.lastPathComponent.lowercased()) {
                let destination = environment.prefixURL
                    .appending(path: "drive_c/windows/\(windowsFolder)", directoryHint: .isDirectory)
                    .appending(path: source.lastPathComponent.lowercased())
                result.append((source, destination))
            }
        }
        return result
    }

    private func manifestURL(_ environment: ManagedBorealEnvironment) -> URL {
        environment.rootURL.appending(path: ".graphics-backend.json")
    }
}
