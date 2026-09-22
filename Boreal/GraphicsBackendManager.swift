import Foundation

nonisolated struct GraphicsBackendActivationSnapshot: Sendable, Equatable {
    nonisolated struct File: Sendable, Equatable {
        let snapshot: URL?
        let destination: URL
    }

    let rootURL: URL
    let manifestData: Data?
    let touchedFiles: [File]
    let backupSnapshotURL: URL?
}

nonisolated struct GraphicsBackendActivation: Sendable, Equatable {
    let backend: WineGraphicsBackend
    let dllOverrides: [String]
    let componentReference: GraphicsComponentReference?
    let rollbackSnapshot: GraphicsBackendActivationSnapshot?

    init(
        backend: WineGraphicsBackend,
        dllOverrides: [String],
        componentReference: GraphicsComponentReference? = nil,
        rollbackSnapshot: GraphicsBackendActivationSnapshot? = nil
    ) {
        self.backend = backend
        self.dllOverrides = dllOverrides
        self.componentReference = componentReference
        self.rollbackSnapshot = rollbackSnapshot
    }
}

nonisolated enum GraphicsBackendManagerError: LocalizedError, Sendable {
    case backendUnavailable(WineGraphicsBackend, GraphicsAPI)
    case componentPackageMissing(WineGraphicsBackend)
    case componentPackageEmpty(WineGraphicsBackend)
    case builtinDXVKPackage
    case activationRollbackFailed(String)

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
        case .activationRollbackFailed(let detail):
            "The graphics backend change failed and Boreal could not fully restore the previous prefix state: \(detail)"
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
        runtime: InstalledRuntime,
        keepRollbackSnapshot: Bool = false
    ) throws -> GraphicsBackendActivation {
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
            return try activateWithoutManagedDLLs(backend, in: environment, keepRollbackSnapshot: keepRollbackSnapshot)
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
        guard supports(backend, runtime: runtime, componentReference: componentReference) else {
            throw GraphicsBackendManagerError.componentPackageMissing(backend)
        }
        guard let componentRoot = componentRoot(
            for: backend,
            api: configuration.api,
            environment: environment,
            runtime: runtime,
            reference: componentReference
        ) else {
            // Imported Wine runtimes can ship DXMT inside Wine.app instead of
            // as a detached Boreal component. The Windows modules and the
            // Unix-side Metal bridge are still a complete renderer.
            guard backend == .dxmt, builtinDXMTAvailable(in: environment, runtime: runtime) else {
                throw GraphicsBackendManagerError.componentPackageMissing(backend)
            }
            let activation = GraphicsBackendActivation(
                backend: .dxmt,
                dllOverrides: Self.apiSpecificDLLOverrides(for: backend, api: configuration.api).sorted(),
                componentReference: nil
            )
            return try activateWithoutManagedDLLs(
                activation,
                in: environment,
                keepRollbackSnapshot: keepRollbackSnapshot
            )
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
        let snapshot = try makeActivationSnapshot(
            in: environment,
            touchedFiles: candidates.map { $0.1 }
        )
        var installed: [InstalledFile] = []
        do {
            try reset(environment)
            if snapshot?.manifestData == nil, fileManager.fileExists(atPath: backupRoot.path) {
                try fileManager.removeItem(at: backupRoot)
            }
            try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
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
        } catch let activationError {
            try? restore(installed.reversed())
            do {
                try restoreActivationSnapshot(snapshot, in: environment)
            } catch let rollbackError {
                throw GraphicsBackendManagerError.activationRollbackFailed(rollbackError.localizedDescription)
            }
            throw activationError
        }

        let installedDLLNames = Set(installed.map {
            $0.destination.deletingPathExtension().lastPathComponent.lowercased()
        })
        let overrides = installedDLLNames
            .intersection(Self.apiSpecificDLLOverrides(for: backend, api: configuration.api))
            .sorted()
        if !keepRollbackSnapshot { discardActivationSnapshot(snapshot) }
        return GraphicsBackendActivation(
            backend: backend,
            dllOverrides: overrides,
            componentReference: componentReference,
            rollbackSnapshot: keepRollbackSnapshot ? snapshot : nil
        )
    }

    func reset(_ environment: ManagedBorealEnvironment) throws {
        let url = manifestURL(environment)
        let backupRoot = environment.rootURL.appending(path: ".graphics-backup", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: url.path) || fileManager.fileExists(atPath: backupRoot.path) else { return }
        let snapshot = try makeActivationSnapshot(in: environment)
        do {
            if fileManager.fileExists(atPath: url.path) {
                let manifest = try JSONDecoder().decode(InstallationManifest.self, from: Data(contentsOf: url))
                try restore(manifest.files.reversed())
                try fileManager.removeItem(at: url)
            }
            if fileManager.fileExists(atPath: backupRoot.path) {
                try fileManager.removeItem(at: backupRoot)
            }
            discardActivationSnapshot(snapshot)
        } catch let resetError {
            do {
                try restoreActivationSnapshot(snapshot, in: environment)
            } catch let rollbackError {
                throw GraphicsBackendManagerError.activationRollbackFailed(rollbackError.localizedDescription)
            }
            throw resetError
        }
    }

    func commit(_ activation: GraphicsBackendActivation) {
        discardActivationSnapshot(activation.rollbackSnapshot)
    }

    func rollback(_ activation: GraphicsBackendActivation, in environment: ManagedBorealEnvironment) throws {
        guard let snapshot = activation.rollbackSnapshot else { return }
        try restoreActivationSnapshot(snapshot, in: environment)
    }

    private func activateWithoutManagedDLLs(
        _ backend: WineGraphicsBackend,
        in environment: ManagedBorealEnvironment,
        keepRollbackSnapshot: Bool = false
    ) throws -> GraphicsBackendActivation {
        try activateWithoutManagedDLLs(
            GraphicsBackendActivation(backend: backend, dllOverrides: []),
            in: environment,
            keepRollbackSnapshot: keepRollbackSnapshot
        )
    }

    private func activateWithoutManagedDLLs(
        _ activation: GraphicsBackendActivation,
        in environment: ManagedBorealEnvironment,
        keepRollbackSnapshot: Bool = false
    ) throws -> GraphicsBackendActivation {
        let snapshot = try makeActivationSnapshot(in: environment)
        do {
            try reset(environment)
            if !keepRollbackSnapshot { discardActivationSnapshot(snapshot) }
            return GraphicsBackendActivation(
                backend: activation.backend,
                dllOverrides: activation.dllOverrides,
                componentReference: activation.componentReference,
                rollbackSnapshot: keepRollbackSnapshot ? snapshot : nil
            )
        } catch let activationError {
            do {
                try restoreActivationSnapshot(snapshot, in: environment)
            } catch let rollbackError {
                throw GraphicsBackendManagerError.activationRollbackFailed(rollbackError.localizedDescription)
            }
            throw activationError
        }
    }

    private func makeActivationSnapshot(
        in environment: ManagedBorealEnvironment,
        touchedFiles: [URL] = []
    ) throws -> GraphicsBackendActivationSnapshot? {
        let url = manifestURL(environment)
        let backupRoot = environment.rootURL.appending(path: ".graphics-backup", directoryHint: .isDirectory)
        let manifestData = fileManager.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        let manifest = try manifestData.map { try JSONDecoder().decode(InstallationManifest.self, from: $0) }
        guard manifestData != nil || fileManager.fileExists(atPath: backupRoot.path) || !touchedFiles.isEmpty else { return nil }
        let prefixPath = environment.prefixURL.standardizedFileURL.path + "/"
        let snapshotRoot = environment.rootURL.appending(
            path: ".graphics-activation-transaction/\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let activeRoot = snapshotRoot.appending(path: "active", directoryHint: .isDirectory)
        var activeFiles: [GraphicsBackendActivationSnapshot.File] = []
        do {
            try fileManager.createDirectory(at: activeRoot, withIntermediateDirectories: true)
            let managedDestinations = (manifest?.files ?? []).map(\.destination)
            let destinations = Array(Set(managedDestinations + touchedFiles.map { $0.standardizedFileURL }))
            for (index, destination) in destinations.enumerated() {
                guard destination.path.hasPrefix(prefixPath) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let saved: URL?
                if fileManager.fileExists(atPath: destination.path) {
                    let values = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    let snapshotFile = activeRoot.appending(path: "\(index)-\(destination.lastPathComponent)")
                    try fileManager.copyItem(at: destination, to: snapshotFile)
                    saved = snapshotFile
                } else {
                    saved = nil
                }
                activeFiles.append(.init(snapshot: saved, destination: destination))
            }
            if let manifestData {
                try manifestData.write(to: snapshotRoot.appending(path: "manifest.json"), options: .atomic)
            }

            let backupSnapshot = snapshotRoot.appending(path: "backup", directoryHint: .isDirectory)
            let backupSnapshotURL: URL?
            if fileManager.fileExists(atPath: backupRoot.path) {
                try fileManager.copyItem(at: backupRoot, to: backupSnapshot)
                backupSnapshotURL = backupSnapshot
            } else {
                backupSnapshotURL = nil
            }
            return GraphicsBackendActivationSnapshot(
                rootURL: snapshotRoot,
                manifestData: manifestData,
                touchedFiles: activeFiles,
                backupSnapshotURL: backupSnapshotURL
            )
        } catch {
            try? fileManager.removeItem(at: snapshotRoot)
            throw error
        }
    }

    private func restoreActivationSnapshot(
        _ snapshot: GraphicsBackendActivationSnapshot?,
        in environment: ManagedBorealEnvironment
    ) throws {
        let url = manifestURL(environment)
        let backupRoot = environment.rootURL.appending(path: ".graphics-backup", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: url.path) {
            let currentManifest = try JSONDecoder().decode(InstallationManifest.self, from: Data(contentsOf: url))
            for file in currentManifest.files.reversed() where fileManager.fileExists(atPath: file.destination.path) {
                try fileManager.removeItem(at: file.destination)
            }
            try fileManager.removeItem(at: url)
        }
        if fileManager.fileExists(atPath: backupRoot.path) {
            try fileManager.removeItem(at: backupRoot)
        }
        guard let snapshot else {
            try? fileManager.removeItem(at: url)
            return
        }
        if let backupSnapshotURL = snapshot.backupSnapshotURL {
            try fileManager.copyItem(at: backupSnapshotURL, to: backupRoot)
        }
        for file in snapshot.touchedFiles {
            if fileManager.fileExists(atPath: file.destination.path) {
                try fileManager.removeItem(at: file.destination)
            }
            if let saved = file.snapshot {
                try fileManager.createDirectory(at: file.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: saved, to: file.destination)
            }
        }
        if let manifestData = snapshot.manifestData {
            try manifestData.write(to: url, options: .atomic)
        } else {
            try? fileManager.removeItem(at: url)
        }
        discardActivationSnapshot(snapshot)
    }

    private func discardActivationSnapshot(_ snapshot: GraphicsBackendActivationSnapshot?) {
        guard let snapshot, fileManager.fileExists(atPath: snapshot.rootURL.path) else { return }
        try? fileManager.removeItem(at: snapshot.rootURL)
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
        // A component reference proves that the package is present, not that
        // its D3D11 implementation can create a device and present a frame.
        // Keep DXMT behind the independent runtime probe even when a profile
        // pins an explicit component version.
        if backend == .dxmt, runtime.features?.d3d11Verified != true {
            return false
        }
        if let componentReference,
           let componentStore,
           componentStore.contains(componentReference, fileManager: fileManager) {
            return true
        }
        return switch backend {
        case .dxmt: runtime.features?.dxmt == true && runtime.features?.d3d11Verified == true
        case .dxvk: runtime.features?.dxvk == true
        case .vkd3d: runtime.features?.vkd3d == true
        default: true
        }
    }

    private func componentRoot(
        for backend: WineGraphicsBackend,
        api: GraphicsAPI,
        environment: ManagedBorealEnvironment,
        runtime: InstalledRuntime,
        reference: GraphicsComponentReference?
    ) -> URL? {
        if let reference,
           let componentStore,
           componentStore.contains(reference, fileManager: fileManager) {
            let referenceRoot = componentStore.componentURL(reference.component, version: reference.version)
            if api != .directX9 || containsD3D9Libraries(in: referenceRoot, environment: environment, runtime: runtime) {
                return referenceRoot
            }
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

    private func containsD3D9Libraries(
        in root: URL,
        environment: ManagedBorealEnvironment,
        runtime: InstalledRuntime
    ) -> Bool {
        let prefixMode = environment.configuration.resolvedPrefixMode(
            runtimeSupportsWoW64: runtime.features?.resolvedArchitectureCapabilities.usesNewWoW64 == true
        )
        let requiredDirectories: [String] = switch prefixMode {
        case .wow64: ["x32", "x64"]
        case .legacyWin32: ["x32"]
        case .legacyWin64: ["x64"]
        }
        return requiredDirectories.allSatisfy { directory in
            fileManager.isReadableFile(
                atPath: root.appending(path: "\(directory)/d3d9.dll").path
            )
        }
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

    static func apiSpecificDLLOverrides(for backend: WineGraphicsBackend, api: GraphicsAPI) -> Set<String> {
        switch (backend, api) {
        case (.dxmt, .directX10):
            ["d3d10", "d3d10_1", "d3d10core", "d3d11", "dxgi"]
        case (.dxmt, .directX11):
            ["d3d11", "dxgi"]
        case (.dxmt, .automatic):
            ["d3d10", "d3d10_1", "d3d10core", "d3d11", "dxgi"]
        case (.dxvk, .directX9):
            ["d3d9", "dxgi"]
        case (.dxvk, .directX10):
            ["d3d10", "d3d10_1", "d3d10core", "dxgi"]
        case (.dxvk, .directX11):
            ["d3d11", "dxgi"]
        case (.dxvk, .automatic):
            ["d3d9", "d3d10", "d3d10_1", "d3d10core", "d3d11", "dxgi"]
        case (.vkd3d, .directX12):
            ["d3d12", "d3d12core", "dxgi"]
        case (.vkd3d, .automatic):
            ["d3d12", "d3d12core", "dxgi"]
        default:
            []
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

    private func builtinDXMTAvailable(
        in environment: ManagedBorealEnvironment,
        runtime: InstalledRuntime
    ) -> Bool {
        let wineLibraries = runtime.rootURL.appending(
            path: "Runtime/Wine.app/Contents/Resources/wine/lib",
            directoryHint: .isDirectory
        )
        let architecture = environment.configuration.resolvedPrefixArchitecture(
            runtimeSupportsWoW64: runtime.features?.resolvedArchitectureCapabilities.usesNewWoW64 == true
        )
        let windowsDirectory = architecture == .win32 ? "i386-windows" : "x86_64-windows"
        let windowsLibraries = wineLibraries
            .appending(path: "wine/\(windowsDirectory)", directoryHint: .isDirectory)
        let unixLibraries = wineLibraries
            .appending(path: "wine/x86_64-unix", directoryHint: .isDirectory)
        return ["d3d11.dll", "dxgi.dll"].allSatisfy {
            fileManager.isReadableFile(atPath: windowsLibraries.appending(path: $0).path)
        } && fileManager.isReadableFile(atPath: unixLibraries.appending(path: "winemetal.so").path)
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
