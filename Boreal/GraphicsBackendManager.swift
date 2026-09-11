import Foundation

nonisolated struct GraphicsBackendActivation: Sendable, Equatable {
    let backend: WineGraphicsBackend
    let dllOverrides: [String]
    let componentReference: GraphicsComponentReference?

    init(
        backend: WineGraphicsBackend,
        dllOverrides: [String],
        componentReference: GraphicsComponentReference? = nil
    ) {
        self.backend = backend
        self.dllOverrides = dllOverrides
        self.componentReference = componentReference
    }
}

nonisolated enum GraphicsBackendManagerError: LocalizedError, Sendable {
    case backendUnavailable(WineGraphicsBackend, GraphicsAPI)
    case componentPackageMissing(WineGraphicsBackend)
    case componentPackageEmpty(WineGraphicsBackend)
    case builtinDXVKPackage

    var errorDescription: String? {
        switch self {
        case .backendUnavailable(let backend, let api):
            "The \(backend.displayName) renderer does not support \(api.displayName) in the selected graphics stack."
        case .componentPackageMissing(let backend):
            "The selected runtime advertises \(backend.displayName), but its graphics component package is missing."
        case .componentPackageEmpty(let backend):
            "The \(backend.displayName) component package does not contain supported Direct3D libraries."
        case .builtinDXVKPackage:
            "This DXVK package contains Wine builtin DLLs, which cannot be activated through prefix overrides. Reinstall DXVK using the runtime component download, or import the archive without 'builtin' in its name."
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
        let componentReference: GraphicsComponentReference?

        init(
            backend: WineGraphicsBackend,
            files: [InstalledFile],
            componentReference: GraphicsComponentReference? = nil
        ) {
            self.backend = backend
            self.files = files
            self.componentReference = componentReference
        }
    }

    private var fileManager: FileManager { .default }
    private let supportedDLLs = Set(["d3d9.dll", "d3d10.dll", "d3d10_1.dll", "d3d10core.dll", "d3d11.dll", "d3d12.dll", "d3d12core.dll", "dxgi.dll", "winemetal.dll"])
    private let componentStore: GraphicsComponentStore?

    init(componentsURL: URL? = nil) {
        componentStore = componentsURL.map { GraphicsComponentStore(rootURL: $0) }
    }

    func resolve(
        _ requested: WineGraphicsBackend,
        graphicsAPI: GraphicsAPI = .automatic,
        runtime: InstalledRuntime,
        architecture: WinePrefixArchitecture = .win64
    ) -> WineGraphicsBackend {
        GraphicsBackendResolver.resolve(
            api: graphicsAPI,
            requestedBackend: requested,
            runtime: runtime,
            architecture: architecture
        ).stack.backend
    }

    func activate(
        _ requested: WineGraphicsBackend,
        in environment: ManagedBorealEnvironment,
        runtime: InstalledRuntime
    ) throws -> GraphicsBackendActivation {
        try reset(environment)
        var configuration = environment.configuration.graphicsConfiguration
        configuration.backend = requested
        let architecture = environment.configuration.resolvedPrefixArchitecture(runtimeSupportsWoW64: runtime.features?.supportsWoW64 == true)
        let resolution = GraphicsBackendResolver.resolve(
            api: configuration.api,
            requestedBackend: requested,
            runtime: runtime,
            architecture: architecture
        )
        guard resolution.isAvailable else {
            throw GraphicsBackendManagerError.backendUnavailable(requested, configuration.api)
        }
        let backend = resolution.stack.backend
        guard backend == .dxmt || backend == .dxvk || backend == .vkd3d else {
            return GraphicsBackendActivation(backend: backend, dllOverrides: [])
        }

        let componentReference = componentReference(
            for: backend,
            environment: environment
        )
        if let configuredReference = environment.configuration.graphicsComponentReferences.first(where: {
            $0.component == component(for: backend)
        }),
           componentStore?.contains(configuredReference, fileManager: fileManager) != true {
            throw GraphicsBackendManagerError.componentPackageMissing(backend)
        }
        guard supports(backend, runtime: runtime, componentReference: componentReference),
              let componentRoot = componentRoot(
                  for: backend,
                  api: configuration.api,
                  runtime: runtime,
                  reference: componentReference
              ) else {
            throw GraphicsBackendManagerError.componentPackageMissing(backend)
        }
        if backend == .dxmt,
           !fileManager.fileExists(atPath: componentRoot.appending(path: "x64-unix/winemetal.so").path) {
            throw GraphicsBackendManagerError.componentPackageEmpty(backend)
        }
        let candidates = try componentFiles(in: componentRoot, environment: environment, runtime: runtime)
        guard !candidates.isEmpty else { throw GraphicsBackendManagerError.componentPackageEmpty(backend) }
        if backend == .dxvk {
            for (source, _) in candidates {
                try Self.validateNativeDXVKLibrary(source)
            }
        }

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
            let manifest = InstallationManifest(
                backend: backend,
                files: installed,
                componentReference: componentReference
            )
            try JSONEncoder().encode(manifest).write(to: manifestURL(environment), options: .atomic)
        } catch {
            try? restore(installed.reversed())
            try? fileManager.removeItem(at: backupRoot)
            throw error
        }

        let overrides = Array(Set(installed.map { $0.destination.deletingPathExtension().lastPathComponent }))
            .filter { $0.caseInsensitiveCompare("winemetal") != .orderedSame }
            .sorted()
        return GraphicsBackendActivation(
            backend: backend,
            dllOverrides: overrides,
            componentReference: componentReference
        )
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
        try JSONEncoder().encode(InstallationManifest(
            backend: manifest.backend,
            files: files,
            componentReference: manifest.componentReference
        ))
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

    private func supports(
        _ backend: WineGraphicsBackend,
        runtime: InstalledRuntime,
        componentReference: GraphicsComponentReference?
    ) -> Bool {
        if let componentReference,
           let componentStore,
           componentStore.contains(componentReference, fileManager: fileManager) {
            return true
        }
        return switch backend {
        case .dxmt: runtime.features?.dxmt == true
        case .dxvk: runtime.features?.dxvk == true
        case .vkd3d: runtime.features?.vkd3d == true
        default: true
        }
    }

    private func componentRoot(
        for backend: WineGraphicsBackend,
        api: GraphicsAPI,
        runtime: InstalledRuntime,
        reference: GraphicsComponentReference?
    ) -> URL? {
        if let reference,
           let componentStore,
           componentStore.contains(reference, fileManager: fileManager) {
            return componentStore.componentURL(reference.component, version: reference.version)
        }
        let folders: [String]
        switch backend {
        case .dxmt: folders = ["DXMT"]
        case .vkd3d: folders = ["VKD3D"]
        case .dxvk:
            // D9VK is persisted as part of the DXVK backend, but older
            // macOS packages can contain both directories while shipping
            // D3D9 only in D9VK. Prefer that component for D3D9 so activation
            // installs the actual library needed by a 32-bit game.
            folders = api == .directX9 ? ["D9VK", "DXVK"] : ["DXVK", "D9VK"]
        default: folders = ["DXVK"]
        }
        return folders.flatMap { folder in
            [
                runtime.rootURL.appending(path: "GraphicsComponents/\(folder)", directoryHint: .isDirectory),
                runtime.rootURL.appending(path: "Support/Graphics/\(folder)", directoryHint: .isDirectory)
            ]
        }.first { fileManager.fileExists(atPath: $0.path) }
    }

    private func componentReference(
        for backend: WineGraphicsBackend,
        environment: ManagedBorealEnvironment
    ) -> GraphicsComponentReference? {
        let component: RuntimeComponent? = switch backend {
        case .dxmt: .dxmt
        case .dxvk: .dxvk
        case .vkd3d: .vkd3d
        default: nil
        }
        guard let component else { return nil }
        if let configured = environment.configuration.graphicsComponentReferences.first(where: { $0.component == component }) {
            return componentStore?.contains(configured, fileManager: fileManager) == true ? configured : nil
        }
        return componentStore?.reference(for: component, fileManager: fileManager)
    }

    private func component(for backend: WineGraphicsBackend) -> RuntimeComponent? {
        switch backend {
        case .dxmt: .dxmt
        case .dxvk: .dxvk
        case .vkd3d: .vkd3d
        default: nil
        }
    }

    private func componentFiles(
        in root: URL,
        environment: ManagedBorealEnvironment,
        runtime: InstalledRuntime
    ) throws -> [(URL, URL)] {
        let layouts: [(String, String)]
        switch environment.configuration.resolvedPrefixMode(runtimeSupportsWoW64: runtime.features?.supportsWoW64 == true) {
        case .wow64:
            // A modern WoW64 prefix keeps 64-bit DLLs in system32 and
            // 32-bit DLLs in syswow64. A requested 32-bit application still
            // uses the combined prefix; do not put an x32 renderer over the
            // 64-bit system32 copy.
            layouts = [("x64", "system32"), ("x32", "syswow64")]
        case .legacyWin32:
            layouts = [("x32", "system32")]
        case .legacyWin64:
            layouts = [("x64", "system32")]
        }
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

    static func validateNativeDXVKLibrary(_ url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 84) ?? Data()
        if header.dropFirst(64).starts(with: Data("Wine builtin DLL".utf8)) {
            throw GraphicsBackendManagerError.builtinDXVKPackage
        }
    }

    private func manifestURL(_ environment: ManagedBorealEnvironment) -> URL {
        environment.rootURL.appending(path: ".graphics-backend.json")
    }
}
