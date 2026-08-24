import Foundation

actor RuntimeManager: RuntimeManaging {
    private let runtimesURL: URL
    private let catalog: any RuntimeCatalogLoading
    private let processExecutor: any ProcessExecuting
    private let requirementChecker: any RuntimeRequirementChecking
    private let session: URLSession
    private let fileManager = FileManager.default

    init(
        applicationSupportURL: URL,
        catalog: any RuntimeCatalogLoading,
        processExecutor: any ProcessExecuting,
        requirementChecker: any RuntimeRequirementChecking,
        session: URLSession = .shared
    ) {
        self.runtimesURL = applicationSupportURL.appending(path: "Runtimes", directoryHint: .isDirectory)
        self.catalog = catalog
        self.processExecutor = processExecutor
        self.requirementChecker = requirementChecker
        self.session = session
    }

    func availableRuntimes() async throws -> [BorealRuntime] { try await catalog.loadCatalog() }

    func installedRuntimes() async throws -> [InstalledRuntime] {
        try prepareDirectories()
        let children = try fileManager.contentsOfDirectory(at: runtimesURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        return children.compactMap { root in
            let descriptor = root.appending(path: "installed-runtime.json")
            guard let data = try? Data(contentsOf: descriptor), var runtime = try? JSONDecoder().decode(InstalledRuntime.self, from: data) else { return nil }
            if runtime.rootURL != root {
                runtime = relocated(runtime, from: runtime.rootURL, to: root)
            }
            return runtime
        }
    }

    func install(_ runtime: BorealRuntime) async throws -> InstalledRuntime {
        try prepareDirectories()
        try validateManifest(runtime)
        let destination = runtimesURL.appending(path: runtime.id, directoryHint: .isDirectory)
        guard !fileManager.fileExists(atPath: destination.path) else { throw RuntimeManagerError.alreadyInstalled(runtime.id) }

        for requirement in runtime.requirements where !(await requirementChecker.isSatisfied(requirement)) {
            throw RuntimeManagerError.requirementMissing(requirement)
        }

        let transactionID = "\(runtime.id)-\(UUID().uuidString)"
        let downloadURL = runtimesURL.appending(path: ".downloads/\(transactionID).tar.xz")
        let staging = runtimesURL.appending(path: ".installing/\(transactionID)", directoryHint: .isDirectory)
        do {
            try await download(runtime.artifact, to: downloadURL)
            let actualHash = try RuntimeSecurity.sha256(of: downloadURL)
            guard actualHash.caseInsensitiveCompare(runtime.artifact.sha256) == .orderedSame else {
                throw RuntimeManagerError.checksumMismatch(expected: runtime.artifact.sha256, actual: actualHash)
            }
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            try await extract(downloadURL, to: staging)
            let provisional = try discoverRuntime(manifest: runtime, root: staging)
            let validation = try await validate(provisional)
            guard validation.isReady else { throw RuntimeManagerError.validationFailed(validation) }

            let relativeWine = try relativePath(of: provisional.wineExecutable, inside: staging)
            let relativeServer = try relativePath(of: provisional.wineServerExecutable, inside: staging)
            let relativeBoot = try relativePath(of: provisional.wineBootExecutable, inside: staging)
            let installed = InstalledRuntime(
                id: runtime.id,
                displayName: runtime.displayName,
                wineVersion: runtime.wineVersion,
                rootURL: destination,
                wineExecutable: destination.appending(path: relativeWine),
                wineServerExecutable: destination.appending(path: relativeServer),
                wineBootExecutable: destination.appending(path: relativeBoot),
                architecture: runtime.architecture,
                requirements: runtime.requirements
            )
            let manifestData = try makeEncoder().encode(runtime)
            try manifestData.write(to: staging.appending(path: "manifest.json"), options: .atomic)
            let descriptorData = try makeEncoder().encode(installed)
            try descriptorData.write(to: staging.appending(path: "installed-runtime.json"), options: .atomic)
            try fileManager.moveItem(at: staging, to: destination)
            try? fileManager.removeItem(at: downloadURL)
            return installed
        } catch {
            if fileManager.fileExists(atPath: downloadURL.path) { try? fileManager.removeItem(at: downloadURL) }
            if fileManager.fileExists(atPath: staging.path) { try? fileManager.removeItem(at: staging) }
            throw error
        }
    }

    func validate(_ runtime: InstalledRuntime) async throws -> RuntimeValidation {
        let executables = [runtime.wineExecutable, runtime.wineServerExecutable, runtime.wineBootExecutable]
        let missing = executables.filter { !fileManager.isExecutableFile(atPath: $0.path) }.map(\.path)
        var unmet: Set<RuntimeRequirement> = []
        for requirement in runtime.requirements where !(await requirementChecker.isSatisfied(requirement)) { unmet.insert(requirement) }
        var detectedVersion: String?
        if missing.isEmpty && unmet.isEmpty {
            let logs = runtime.rootURL.appending(path: ".validation")
            let request = ProcessLaunchRequest(
                executable: runtime.wineExecutable,
                arguments: ["--version"],
                environment: runtimeEnvironment(runtime),
                currentDirectory: runtime.rootURL,
                stdoutLog: logs.appending(path: "wine-version.stdout.log"),
                stderrLog: logs.appending(path: "wine-version.stderr.log")
            )
            if let receipt = try? await processExecutor.launch(request),
               let result = try? await processExecutor.waitForExit(receipt.id), result.exitCode == 0,
               let output = try? String(contentsOf: result.stdoutLog, encoding: .utf8) {
                detectedVersion = output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return RuntimeValidation(detectedWineVersion: detectedVersion, versionMatchesManifest: detectedVersion?.contains(runtime.wineVersion) == true, missingPaths: missing, unmetRequirements: unmet, executablePaths: executables.map(\.path))
    }

    func remove(_ runtime: InstalledRuntime) async throws {
        let standardizedRoot = runtime.rootURL.standardizedFileURL
        guard standardizedRoot.deletingLastPathComponent() == runtimesURL.standardizedFileURL else { throw RuntimeManagerError.runtimeLayoutNotFound }
        try fileManager.removeItem(at: standardizedRoot)
    }

    private func prepareDirectories() throws {
        try fileManager.createDirectory(at: runtimesURL.appending(path: ".downloads"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: runtimesURL.appending(path: ".installing"), withIntermediateDirectories: true)
    }

    private func validateManifest(_ runtime: BorealRuntime) throws {
        guard runtime.schemaVersion == 1,
              !runtime.id.isEmpty,
              !runtime.id.contains("/"),
              !runtime.id.contains(".."),
              runtime.artifact.sha256.count == 64,
              runtime.artifact.sha256.allSatisfy({ $0.isHexDigit }),
              runtime.artifact.compressedSize >= 0,
              runtime.artifact.url.isFileURL || runtime.artifact.url.scheme == "https" else {
            throw RuntimeManagerError.invalidManifest
        }
        let parts = runtime.minimumMacOS.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { throw RuntimeManagerError.invalidManifest }
        let required = OperatingSystemVersion(majorVersion: parts[0], minorVersion: parts.count > 1 ? parts[1] : 0, patchVersion: parts.count > 2 ? parts[2] : 0)
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(required) else { throw RuntimeManagerError.invalidManifest }
    }

    private func download(_ artifact: RuntimeArtifact, to destination: URL) async throws {
        if artifact.url.isFileURL {
            try fileManager.copyItem(at: artifact.url, to: destination)
            return
        }
        let (temporary, response) = try await session.download(from: artifact.url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw RuntimeManagerError.downloadFailed("The server returned an unexpected response.")
        }
        if artifact.compressedSize > 0 && response.expectedContentLength > 0 && response.expectedContentLength != artifact.compressedSize {
            throw RuntimeManagerError.downloadFailed("The artifact size does not match its manifest.")
        }
        try fileManager.moveItem(at: temporary, to: destination)
    }

    private func extract(_ archive: URL, to destination: URL) async throws {
        guard archive.lastPathComponent.hasSuffix(".tar.xz") else { throw RuntimeManagerError.unsupportedArchive }
        let request = ProcessLaunchRequest(
            executable: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-xJf", archive.path, "-C", destination.path],
            environment: ProcessInfo.processInfo.environment,
            stdoutLog: destination.appending(path: "extract.stdout.log"),
            stderrLog: destination.appending(path: "extract.stderr.log")
        )
        let receipt = try await processExecutor.launch(request)
        let result = try await processExecutor.waitForExit(receipt.id)
        guard result.exitCode == 0 else { throw RuntimeManagerError.unsupportedArchive }
    }

    private func discoverRuntime(manifest: BorealRuntime, root: URL) throws -> InstalledRuntime {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isExecutableKey]
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { throw RuntimeManagerError.runtimeLayoutNotFound }
        var wine: URL?
        var server: URL?
        var boot: URL?
        for case let url as URL in enumerator {
            guard fileManager.isExecutableFile(atPath: url.path) else { continue }
            switch url.lastPathComponent {
            case "wine" where url.path.contains("/wine/bin/"): wine = wine ?? url
            case "wineserver" where url.path.contains("/wine/bin/"): server = server ?? url
            case "wineboot" where url.path.contains("/wine/bin/"): boot = boot ?? url
            default: break
            }
        }
        guard let wine, let server, let boot else { throw RuntimeManagerError.runtimeLayoutNotFound }
        return InstalledRuntime(id: manifest.id, displayName: manifest.displayName, wineVersion: manifest.wineVersion, rootURL: root, wineExecutable: wine, wineServerExecutable: server, wineBootExecutable: boot, architecture: manifest.architecture, requirements: manifest.requirements)
    }

    private func runtimeEnvironment(_ runtime: InstalledRuntime) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let bin = runtime.wineExecutable.deletingLastPathComponent().path
        environment["PATH"] = bin + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        return environment
    }

    private func relocated(_ runtime: InstalledRuntime, from oldRoot: URL, to newRoot: URL) -> InstalledRuntime {
        func move(_ url: URL) -> URL {
            let relative = (try? relativePath(of: url, inside: oldRoot)) ?? url.lastPathComponent
            return newRoot.appending(path: relative)
        }
        return InstalledRuntime(id: runtime.id, displayName: runtime.displayName, wineVersion: runtime.wineVersion, rootURL: newRoot, wineExecutable: move(runtime.wineExecutable), wineServerExecutable: move(runtime.wineServerExecutable), wineBootExecutable: move(runtime.wineBootExecutable), architecture: runtime.architecture, requirements: runtime.requirements)
    }

    private func relativePath(of child: URL, inside root: URL) throws -> String {
        let childComponents = child.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let rootComponents = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard childComponents.count > rootComponents.count,
              Array(childComponents.prefix(rootComponents.count)) == rootComponents else {
            throw RuntimeManagerError.runtimeLayoutNotFound
        }
        return childComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
