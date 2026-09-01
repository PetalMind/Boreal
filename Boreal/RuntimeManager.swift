import Foundation

actor RuntimeManager: RuntimeManaging {
    private let runtimesURL: URL
    private let catalog: any RuntimeCatalogLoading
    private let processExecutor: any ProcessExecuting
    private let requirementChecker: any RuntimeRequirementChecking
    private let session: URLSession
    private let localApplicationRoots: [URL]
    private let fileManager = FileManager.default

    init(
        applicationSupportURL: URL,
        catalog: any RuntimeCatalogLoading,
        processExecutor: any ProcessExecuting,
        requirementChecker: any RuntimeRequirementChecking,
        session: URLSession = .shared,
        localApplicationRoots: [URL]? = nil
    ) {
        self.runtimesURL = applicationSupportURL.appending(path: "Runtimes", directoryHint: .isDirectory)
        self.catalog = catalog
        self.processExecutor = processExecutor
        self.requirementChecker = requirementChecker
        self.session = session
        self.localApplicationRoots = localApplicationRoots ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory)
        ]
    }

    func availableRuntimes() async throws -> [BorealRuntime] { try await catalog.loadCatalog() }

    func localRuntimeCandidates() async -> [LocalRuntimeCandidate] {
        var candidates: [LocalRuntimeCandidate] = []
        var seen = Set<String>()
        for root in localApplicationRoots {
            guard let apps = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for app in apps where app.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                let info = Bundle(url: app)?.infoDictionary
                let name = (info?["CFBundleDisplayName"] as? String)
                    ?? (info?["CFBundleName"] as? String)
                    ?? app.deletingPathExtension().lastPathComponent
                let engine = detectEngine(app: app, name: name)
                let relativeWine = firstExecutable(in: app, candidates: [
                    "Contents/Resources/wine/bin/wine",
                    "Contents/Resources/wine/bin/wine64",
                    "Contents/MacOS/wine"
                ])
                guard let relativeWine else { continue }
                let wine = app.appending(path: relativeWine)
                let server = app.appending(path: "Contents/Resources/wine/bin/wineserver")
                let relativeBoot = "Contents/Resources/wine/bin/wineboot"
                let boot = app.appending(path: relativeBoot)
                let usesGeneratedGPTKWineBoot = engine == .gamePortingToolkit
                    && !fileManager.fileExists(atPath: boot.path)
                guard [wine, server].allSatisfy({ fileManager.isExecutableFile(atPath: $0.path) }),
                      (fileManager.isExecutableFile(atPath: boot.path) || usesGeneratedGPTKWineBoot),
                      let architecture = executableArchitecture(at: wine) else { continue }
                let version = (info?["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let version, !version.isEmpty else { continue }
                let minimumMacOS = (info?["LSMinimumSystemVersion"] as? String) ?? "10.15"
                var requirements = Set<RuntimeRequirement>()
                #if arch(arm64)
                if architecture == .x86_64 { requirements.insert(.rosetta2) }
                #endif
                let id = localRuntimeID(name: name, version: version, architecture: architecture)
                guard seen.insert(id).inserted else { continue }
                let supportsWoW64 = detectsWoW64(in: app)
                candidates.append(LocalRuntimeCandidate(
                    id: id,
                    displayName: name,
                    wineVersion: version,
                    appURL: app,
                    architecture: architecture,
                    requirements: requirements,
                    minimumMacOS: minimumMacOS,
                    estimatedSize: nil,
                    engine: engine,
                    features: RuntimeFeatures(wow64: supportsWoW64, wineMono: false, wineGecko: false, d3dmetal: engine == .gamePortingToolkit, dxmt: false),
                    layout: RuntimeLayout(
                        wineExecutable: "Runtime/Wine.app/\(relativeWine)",
                        wineServerExecutable: "Runtime/Wine.app/Contents/Resources/wine/bin/wineserver",
                        wineBootExecutable: usesGeneratedGPTKWineBoot
                            ? "Support/wineboot"
                            : "Runtime/Wine.app/\(relativeBoot)",
                        dependenciesDirectory: "Dependencies",
                        supportDirectory: "Support",
                        licensesDirectory: "Licenses",
                        noticesFile: "Licenses/THIRD_PARTY_NOTICES.txt",
                        sbomFile: "SBOM.spdx.json"
                    )
                ))
            }
        }
        return candidates.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func installedRuntimes() async throws -> [InstalledRuntime] {
        try prepareDirectories()
        let children = try fileManager.contentsOfDirectory(at: runtimesURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        return children.compactMap { root in
            let descriptor = root.appending(path: "installed-runtime.json")
            guard let data = try? Data(contentsOf: descriptor), var runtime = try? JSONDecoder().decode(InstalledRuntime.self, from: data) else { return nil }
            if runtime.rootURL != root {
                runtime = relocated(runtime, from: runtime.rootURL, to: root)
            }
            return refreshingDetectedFeatures(of: runtime)
        }
    }

    func importLocalRuntime(_ candidate: LocalRuntimeCandidate) async throws -> InstalledRuntime {
        try prepareDirectories()
        guard !candidate.id.isEmpty, !candidate.id.contains("/"), !candidate.id.contains("..") else {
            throw RuntimeManagerError.localRuntimeInvalid("Its generated identifier is unsafe.")
        }
        let source = candidate.appURL.standardizedFileURL
        let allowedRoots = localApplicationRoots.map(\.standardizedFileURL)
        guard allowedRoots.contains(where: { source.deletingLastPathComponent() == $0 }),
              source.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            throw RuntimeManagerError.localRuntimeInvalid("Only Wine apps installed directly in an Applications folder are supported.")
        }
        let copiedPrefix = "Runtime/Wine.app/"
        guard candidate.layout.wineExecutable.hasPrefix(copiedPrefix) else {
            throw RuntimeManagerError.localRuntimeInvalid("Its runtime layout is invalid.")
        }
        let sourceWine = source.appending(path: String(candidate.layout.wineExecutable.dropFirst(copiedPrefix.count)))
        guard fileManager.isExecutableFile(atPath: sourceWine.path) else {
            throw RuntimeManagerError.localRuntimeInvalid("The Wine executable is missing.")
        }
        var detectedFeatures = candidate.features
        detectedFeatures.wow64 = detectsWoW64(in: source)
        for requirement in candidate.requirements where !(await requirementChecker.isSatisfied(requirement)) {
            throw RuntimeManagerError.requirementMissing(requirement)
        }

        let destination = runtimesURL.appending(path: candidate.id, directoryHint: .isDirectory)
        guard !fileManager.fileExists(atPath: destination.path) else { throw RuntimeManagerError.alreadyInstalled(candidate.id) }
        let staging = runtimesURL.appending(path: ".installing/\(candidate.id)-\(UUID().uuidString)", directoryHint: .isDirectory)
        let runtimeDirectory = staging.appending(path: "Runtime", directoryHint: .isDirectory)
        let copiedApp = runtimeDirectory.appending(path: "Wine.app", directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: copiedApp)
            try fileManager.createDirectory(at: staging.appending(path: "Dependencies", directoryHint: .isDirectory), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: staging.appending(path: "Support", directoryHint: .isDirectory), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: staging.appending(path: "Licenses", directoryHint: .isDirectory), withIntermediateDirectories: true)

            let notice = """
            Boreal local runtime snapshot

            Imported from: \(source.path)
            Product: \(candidate.displayName) \(candidate.wineVersion)
            Boreal copied this user-installed app and does not distribute or attest its original package.
            Wine is free software. License and source information: https://www.winehq.org/source/
            """
            try Data(notice.utf8).write(to: staging.appending(path: RuntimeLayout.canonical.noticesFile), options: .atomic)
            let sbom: [String: Any] = [
                "spdxVersion": "SPDX-2.3",
                "dataLicense": "CC0-1.0",
                "SPDXID": "SPDXRef-DOCUMENT",
                "name": "\(candidate.displayName)-local-snapshot",
                "documentNamespace": "https://boreal.local/spdx/\(candidate.id)/\(UUID().uuidString)",
                "creationInfo": ["creators": ["Tool: Boreal"], "created": ISO8601DateFormatter().string(from: Date())],
                "packages": [[
                    "name": candidate.displayName,
                    "SPDXID": "SPDXRef-Package-Wine",
                    "versionInfo": candidate.wineVersion,
                    "downloadLocation": "NOASSERTION",
                    "filesAnalyzed": false,
                    "licenseConcluded": "NOASSERTION",
                    "licenseDeclared": "NOASSERTION",
                    "copyrightText": "NOASSERTION"
                ]]
            ]
            try JSONSerialization.data(withJSONObject: sbom, options: [.prettyPrinted, .sortedKeys])
                .write(to: staging.appending(path: RuntimeLayout.canonical.sbomFile), options: .atomic)

            if candidate.engine == .gamePortingToolkit,
               candidate.layout.wineBootExecutable == "Support/wineboot" {
                let wrapper = staging.appending(path: candidate.layout.wineBootExecutable)
                let script = """
                #!/bin/sh
                exec "$(dirname "$0")/../Runtime/Wine.app/Contents/Resources/wine/bin/wine64" wineboot "$@"
                """
                try Data(script.utf8).write(to: wrapper, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
            }

            let localManifest = BorealRuntime(
                schemaVersion: 1,
                id: candidate.id,
                displayName: "\(candidate.displayName) (Local Snapshot)",
                wineVersion: candidate.wineVersion,
                architecture: candidate.architecture,
                minimumMacOS: candidate.minimumMacOS,
                channel: .preview,
                requirements: candidate.requirements,
                features: detectedFeatures,
                layout: candidate.layout,
                artifact: RuntimeArtifact(url: source, sha256: String(repeating: "0", count: 64), compressedSize: 0)
            )
            try makeEncoder().encode(localManifest.packageManifest)
                .write(to: staging.appending(path: "runtime.json"), options: .atomic)
            try validateExtractedTree(staging)
            let provisional = try resolveRuntime(manifest: localManifest, root: staging)
            // Requirements were checked against the source immediately before
            // starting this transaction. Do not repeat a platform probe after
            // the expensive copy: Rosetta detection is an external check and a
            // transient second failure must not invalidate a sound snapshot.
            let validation = try await validate(provisional, checkingRequirements: false)
            guard validation.isReady else { throw RuntimeManagerError.validationFailed(validation) }
            try await smokeTest(provisional)

            let installed = InstalledRuntime(
                id: candidate.id,
                displayName: localManifest.displayName,
                wineVersion: candidate.wineVersion,
                rootURL: destination,
                wineExecutable: destination.appending(path: candidate.layout.wineExecutable),
                wineServerExecutable: destination.appending(path: candidate.layout.wineServerExecutable),
                wineBootExecutable: destination.appending(path: candidate.layout.wineBootExecutable),
                architecture: candidate.architecture,
                requirements: candidate.requirements,
                origin: .localImport,
                engine: candidate.engine,
                features: detectedFeatures
            )
            try makeEncoder().encode(installed)
                .write(to: staging.appending(path: "installed-runtime.json"), options: .atomic)
            try fileManager.moveItem(at: staging, to: destination)
            try makeImmutable(destination)
            return installed
        } catch {
            if fileManager.fileExists(atPath: staging.path) {
                try? makeWritable(staging)
                try? fileManager.removeItem(at: staging)
            }
            if fileManager.fileExists(atPath: destination.path) {
                try? makeWritable(destination)
                try? fileManager.removeItem(at: destination)
            }
            throw error
        }
    }

    func install(_ runtime: BorealRuntime) async throws -> InstalledRuntime {
        try prepareDirectories()
        try validateManifest(runtime)
        let destination = runtimesURL.appending(path: runtime.id, directoryHint: .isDirectory)
        guard !fileManager.fileExists(atPath: destination.path) else { throw RuntimeManagerError.alreadyInstalled(runtime.id) }

        if runtime.requirements.contains(.gStreamerFramework) {
            throw RuntimeManagerError.nonSelfContained(.gStreamerFramework)
        }
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
            try validateExtractedTree(staging)
            let packageManifestURL = staging.appending(path: "runtime.json")
            guard let packageData = try? Data(contentsOf: packageManifestURL),
                  let packageManifest = try? JSONDecoder().decode(RuntimePackageManifest.self, from: packageData),
                  packageManifest == runtime.packageManifest else {
                throw RuntimeManagerError.packageManifestMismatch
            }
            let provisional = try resolveRuntime(manifest: runtime, root: staging)
            let validation = try await validate(provisional)
            guard validation.isReady else { throw RuntimeManagerError.validationFailed(validation) }
            try await smokeTest(provisional)

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
                requirements: runtime.requirements,
                engine: runtime.features.d3dmetal ? .gamePortingToolkit : .wine,
                features: runtime.features
            )
            let descriptorData = try makeEncoder().encode(installed)
            try descriptorData.write(to: staging.appending(path: "installed-runtime.json"), options: .atomic)
            try fileManager.moveItem(at: staging, to: destination)
            try makeImmutable(destination)
            try? fileManager.removeItem(at: downloadURL)
            return installed
        } catch {
            if fileManager.fileExists(atPath: downloadURL.path) { try? fileManager.removeItem(at: downloadURL) }
            if fileManager.fileExists(atPath: staging.path) {
                try? makeWritable(staging)
                try? fileManager.removeItem(at: staging)
            }
            if fileManager.fileExists(atPath: destination.path) {
                try? makeWritable(destination)
                try? fileManager.removeItem(at: destination)
            }
            throw error
        }
    }

    func validate(_ runtime: InstalledRuntime) async throws -> RuntimeValidation {
        try await validate(runtime, checkingRequirements: true)
    }

    private func validate(_ runtime: InstalledRuntime, checkingRequirements: Bool) async throws -> RuntimeValidation {
        let executables = [runtime.wineExecutable, runtime.wineServerExecutable, runtime.wineBootExecutable]
        var missing = executables.filter { !fileManager.isExecutableFile(atPath: $0.path) }.map(\.path)
        let metadata = runtime.rootURL.appending(path: "runtime.json")
        if let data = try? Data(contentsOf: metadata),
           let manifest = try? JSONDecoder().decode(RuntimePackageManifest.self, from: data) {
            for path in [manifest.layout.dependenciesDirectory, manifest.layout.supportDirectory, manifest.layout.licensesDirectory, manifest.layout.noticesFile, manifest.layout.sbomFile] {
                if let required = try? containedURL(path, root: runtime.rootURL), !fileManager.fileExists(atPath: required.path) { missing.append(required.path) }
            }
        } else {
            missing.append(metadata.path)
        }
        var unmet: Set<RuntimeRequirement> = []
        if checkingRequirements {
            for requirement in runtime.requirements {
                if requirement == .gStreamerFramework {
                    unmet.insert(requirement)
                } else if !(await requirementChecker.isSatisfied(requirement)) {
                    unmet.insert(requirement)
                }
            }
        }
        var detectedVersion: String?
        if missing.isEmpty && unmet.isEmpty {
            let logs = runtimesURL.appending(path: ".validation/\(runtime.id)", directoryHint: .isDirectory)
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
        let versionMatchesManifest: Bool
        if runtime.resolvedEngine == .gamePortingToolkit {
            // GPTK's app bundle version (for example 3.0-2) intentionally
            // differs from the embedded Wine version string (for example
            // wine-7.7 (Game Porting Toolkit 1.1)). Confirm the engine
            // identity here; the package version remains sourced from the
            // copied app's signed Info.plist metadata.
            versionMatchesManifest = detectedVersion?.localizedCaseInsensitiveContains("Game Porting Toolkit") == true
        } else {
            versionMatchesManifest = detectedVersion?.contains(runtime.wineVersion) == true
        }
        return RuntimeValidation(detectedWineVersion: detectedVersion, versionMatchesManifest: versionMatchesManifest, missingPaths: missing, unmetRequirements: unmet, executablePaths: executables.map(\.path))
    }

    func remove(_ runtime: InstalledRuntime) async throws {
        let standardizedRoot = runtime.rootURL.standardizedFileURL
        guard standardizedRoot.deletingLastPathComponent() == runtimesURL.standardizedFileURL else { throw RuntimeManagerError.runtimeLayoutNotFound }
        try makeWritable(standardizedRoot)
        try fileManager.removeItem(at: standardizedRoot)
    }

    private func prepareDirectories() throws {
        try fileManager.createDirectory(at: runtimesURL.appending(path: ".downloads"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: runtimesURL.appending(path: ".installing"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: runtimesURL.appending(path: ".validation"), withIntermediateDirectories: true)
    }

    private func validateManifest(_ runtime: BorealRuntime) throws {
        guard runtime.schemaVersion == 1,
              !runtime.id.isEmpty,
              !runtime.id.contains("/"),
              !runtime.id.contains(".."),
              runtime.artifact.sha256.count == 64,
              runtime.artifact.sha256.allSatisfy({ $0.isHexDigit }),
              runtime.artifact.compressedSize >= 0,
              runtime.borealRevision > 0,
              runtime.artifact.url.isFileURL || runtime.artifact.url.scheme == "https" else {
            throw RuntimeManagerError.invalidManifest
        }
        guard !runtime.requirements.contains(.gStreamerFramework),
              secureRelativePaths(runtime.layout).allSatisfy({ $0 }) else {
            throw RuntimeManagerError.invalidManifest
        }
        guard runtime.features.wineMono == (runtime.components.mono != nil),
              runtime.features.wineGecko == (runtime.components.gecko != nil) else {
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
            try validateDownloadedSize(artifact, at: destination)
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
        try validateDownloadedSize(artifact, at: destination)
    }

    private func extract(_ archive: URL, to destination: URL) async throws {
        guard archive.lastPathComponent.hasSuffix(".tar.xz") else { throw RuntimeManagerError.unsupportedArchive }
        let listing = try await archiveListing(archive, logs: destination)
        for entry in listing.split(whereSeparator: \.isNewline).map(String.init) {
            let normalized = entry.hasPrefix("./") ? String(entry.dropFirst(2)) : entry
            if normalized.hasPrefix("/") || normalized.split(separator: "/").contains("..") {
                throw RuntimeManagerError.unsafeArchive(entry)
            }
        }
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

    private func resolveRuntime(manifest: BorealRuntime, root: URL) throws -> InstalledRuntime {
        let wine = try containedURL(manifest.layout.wineExecutable, root: root)
        let server = try containedURL(manifest.layout.wineServerExecutable, root: root)
        let boot = try containedURL(manifest.layout.wineBootExecutable, root: root)
        guard [wine, server, boot].allSatisfy({ fileManager.isExecutableFile(atPath: $0.path) }) else { throw RuntimeManagerError.runtimeLayoutNotFound }
        for path in [manifest.layout.dependenciesDirectory, manifest.layout.supportDirectory, manifest.layout.licensesDirectory, manifest.layout.noticesFile, manifest.layout.sbomFile] {
            guard fileManager.fileExists(atPath: try containedURL(path, root: root).path) else { throw RuntimeManagerError.runtimeLayoutNotFound }
        }
        if manifest.features.wineMono { guard fileManager.fileExists(atPath: try containedURL(manifest.layout.supportDirectory + "/wine-mono", root: root).path) else { throw RuntimeManagerError.runtimeLayoutNotFound } }
        if manifest.features.wineGecko { guard fileManager.fileExists(atPath: try containedURL(manifest.layout.supportDirectory + "/wine-gecko", root: root).path) else { throw RuntimeManagerError.runtimeLayoutNotFound } }
        return InstalledRuntime(id: manifest.id, displayName: manifest.displayName, wineVersion: manifest.wineVersion, rootURL: root, wineExecutable: wine, wineServerExecutable: server, wineBootExecutable: boot, architecture: manifest.architecture, requirements: manifest.requirements, engine: manifest.features.d3dmetal ? .gamePortingToolkit : .wine, features: manifest.features)
    }

    private func smokeTest(_ runtime: InstalledRuntime) async throws {
        let prefix = runtimesURL.appending(path: ".installing/smoke-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: prefix, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: prefix) }
        var environment = runtimeEnvironment(runtime)
        environment["WINEPREFIX"] = prefix.path
        environment["WINEDEBUG"] = "-all"
        let request = ProcessLaunchRequest(
            executable: runtime.wineBootExecutable,
            arguments: ["--init"],
            environment: environment,
            currentDirectory: prefix,
            stdoutLog: prefix.appending(path: "wineboot.stdout.log"),
            stderrLog: prefix.appending(path: "wineboot.stderr.log")
        )
        do {
            let receipt = try await processExecutor.launch(request)
            let result = try await processExecutor.waitForExit(receipt.id)
            guard result.exitCode == 0 else {
                throw RuntimeManagerError.validationFailed(RuntimeValidation(
                    detectedWineVersion: runtime.wineVersion,
                    versionMatchesManifest: true,
                    missingPaths: ["wineboot smoke test exited with \(result.exitCode)"],
                    unmetRequirements: [],
                    executablePaths: [runtime.wineBootExecutable.path]
                ))
            }
            let expectedPrefixPaths = [
                prefix.appending(path: "drive_c", directoryHint: .isDirectory),
                prefix.appending(path: "dosdevices", directoryHint: .isDirectory),
                prefix.appending(path: "system.reg"),
                prefix.appending(path: "user.reg"),
                prefix.appending(path: "userdef.reg")
            ]
            // WineHQ can return from wineboot before its server has flushed all
            // registry files. Give the isolated prefix up to two minutes.
            for _ in 0..<480 {
                try Task.checkCancellation()
                if expectedPrefixPaths.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) { break }
                try await Task.sleep(for: .milliseconds(250))
            }
            let missing = expectedPrefixPaths.filter { !fileManager.fileExists(atPath: $0.path) }.map(\.path)
            guard missing.isEmpty else {
                throw RuntimeManagerError.validationFailed(RuntimeValidation(
                    detectedWineVersion: runtime.wineVersion,
                    versionMatchesManifest: true,
                    missingPaths: missing,
                    unmetRequirements: [],
                    executablePaths: [runtime.wineBootExecutable.path]
                ))
            }
        } catch {
            await stopWineServer(runtime, environment: environment, prefix: prefix)
            throw error
        }
        await stopWineServer(runtime, environment: environment, prefix: prefix)
    }

    private func stopWineServer(_ runtime: InstalledRuntime, environment: [String: String], prefix: URL) async {
        let serverRequest = ProcessLaunchRequest(
            executable: runtime.wineServerExecutable,
            arguments: ["-k"],
            environment: environment,
            currentDirectory: prefix,
            stdoutLog: prefix.appending(path: "wineserver.stdout.log"),
            stderrLog: prefix.appending(path: "wineserver.stderr.log")
        )
        if let server = try? await processExecutor.launch(serverRequest) { _ = try? await processExecutor.waitForExit(server.id) }
    }

    private func archiveListing(_ archive: URL, logs: URL) async throws -> String {
        let request = ProcessLaunchRequest(
            executable: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-tJf", archive.path],
            environment: ProcessInfo.processInfo.environment,
            stdoutLog: logs.appending(path: "listing.stdout.log"),
            stderrLog: logs.appending(path: "listing.stderr.log")
        )
        let receipt = try await processExecutor.launch(request)
        let result = try await processExecutor.waitForExit(receipt.id)
        guard result.exitCode == 0 else { throw RuntimeManagerError.unsupportedArchive }
        return try String(contentsOf: result.stdoutLog, encoding: .utf8)
    }

    private func validateDownloadedSize(_ artifact: RuntimeArtifact, at url: URL) throws {
        guard artifact.compressedSize > 0 else { return }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) ?? -1
        guard size == artifact.compressedSize else { throw RuntimeManagerError.downloadFailed("The downloaded artifact size does not match its manifest.") }
    }

    private func containedURL(_ relativePath: String, root: URL) throws -> URL {
        guard isSecureRelativePath(relativePath) else { throw RuntimeManagerError.runtimeLayoutNotFound }
        let candidate = root.appending(path: relativePath).standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedCandidate.path.hasPrefix(canonicalRoot.path + "/") else { throw RuntimeManagerError.runtimeLayoutNotFound }
        return candidate
    }

    private func secureRelativePaths(_ layout: RuntimeLayout) -> [Bool] {
        [layout.wineExecutable, layout.wineServerExecutable, layout.wineBootExecutable, layout.dependenciesDirectory, layout.supportDirectory, layout.licensesDirectory, layout.noticesFile, layout.sbomFile].map(isSecureRelativePath)
    }

    private func isSecureRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }

    private func makeImmutable(_ root: URL) throws {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) else { return }
        var urls = [root]
        for case let url as URL in enumerator { urls.append(url) }
        for url in urls.reversed() {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { continue }
            let isDirectory = values?.isDirectory == true
            let executable = !isDirectory && fileManager.isExecutableFile(atPath: url.path)
            try fileManager.setAttributes([.posixPermissions: isDirectory || executable ? 0o555 : 0o444], ofItemAtPath: url.path)
        }
    }

    private func makeWritable(_ root: URL) throws {
        guard fileManager.fileExists(atPath: root.path) else { return }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isExecutableKey, .isSymbolicLinkKey], options: []) else { return }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isExecutableKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { continue }
            let permissions = values.isDirectory == true || values.isExecutable == true ? 0o755 : 0o644
            try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }

    private func validateExtractedTree(_ root: URL) throws {
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) else { return }
        for case let url as URL in enumerator {
            if (try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                let target = url.resolvingSymlinksInPath().standardizedFileURL
                guard target.path.hasPrefix(canonicalRoot.path + "/") else { throw RuntimeManagerError.unsafeArchive(url.path) }
            }
        }
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
        return InstalledRuntime(id: runtime.id, displayName: runtime.displayName, wineVersion: runtime.wineVersion, rootURL: newRoot, wineExecutable: move(runtime.wineExecutable), wineServerExecutable: move(runtime.wineServerExecutable), wineBootExecutable: move(runtime.wineBootExecutable), architecture: runtime.architecture, requirements: runtime.requirements, origin: runtime.origin, engine: runtime.engine, features: runtime.features)
    }

    private func firstExecutable(in app: URL, candidates: [String]) -> String? {
        candidates.first { fileManager.isExecutableFile(atPath: app.appending(path: $0).path) }
    }

    private func detectEngine(app: URL, name: String) -> RuntimeEngine {
        let normalizedName = name.lowercased()
        if normalizedName.contains("game porting toolkit") || normalizedName.contains("gptk") { return .gamePortingToolkit }
        let resources = app.appending(path: "Contents/Resources")
        let markers = [
            "wine/lib/external/libD3DMetal.dylib",
            "wine/lib/external/D3DMetal.framework/Versions/A/D3DMetal"
        ]
        return markers.contains(where: { fileManager.fileExists(atPath: resources.appending(path: $0).path) }) ? .gamePortingToolkit : .wine
    }

    /// Local Wine bundles are not backed by Boreal's signed catalog, so their
    /// 32-bit support must come from the copied runtime itself. Current WineHQ
    /// builds use the new WoW64 layout, while older combined builds expose a
    /// separate wine64 launcher alongside the 32-bit Windows modules.
    private func detectsWoW64(in app: URL) -> Bool {
        let wineRoot = app.appending(path: "Contents/Resources/wine", directoryHint: .isDirectory)
        let has32BitWindowsNTDLL = fileManager.fileExists(
            atPath: wineRoot.appending(path: "lib/wine/i386-windows/ntdll.dll").path
        )
        guard has32BitWindowsNTDLL else { return false }

        let hasNewWoW64CPU = fileManager.fileExists(
            atPath: wineRoot.appending(path: "lib/wine/x86_64-windows/wow64cpu.dll").path
        )
        let hasLegacyWine64 = fileManager.isExecutableFile(
            atPath: wineRoot.appending(path: "bin/wine64").path
        )
        return hasNewWoW64CPU || hasLegacyWine64
    }

    /// Runtime snapshots imported by older Boreal builds can contain a stale
    /// `wow64: false` descriptor. Keep the immutable snapshot intact and
    /// refresh only the in-memory capability from its copied payload.
    private func refreshingDetectedFeatures(of runtime: InstalledRuntime) -> InstalledRuntime {
        guard runtime.origin == .localImport else { return runtime }
        let copiedApp = runtime.rootURL.appending(path: "Runtime/Wine.app", directoryHint: .isDirectory)
        var features = runtime.features ?? RuntimeFeatures(
            wow64: false,
            wineMono: false,
            wineGecko: false,
            d3dmetal: runtime.resolvedEngine == .gamePortingToolkit,
            dxmt: false
        )
        features.wow64 = detectsWoW64(in: copiedApp)
        return InstalledRuntime(
            id: runtime.id,
            displayName: runtime.displayName,
            wineVersion: runtime.wineVersion,
            rootURL: runtime.rootURL,
            wineExecutable: runtime.wineExecutable,
            wineServerExecutable: runtime.wineServerExecutable,
            wineBootExecutable: runtime.wineBootExecutable,
            architecture: runtime.architecture,
            requirements: runtime.requirements,
            origin: runtime.origin,
            engine: runtime.engine,
            features: features
        )
    }

    private func localRuntimeID(name: String, version: String, architecture: RuntimeArchitecture) -> String {
        let raw = "local-\(name)-\(version)-\(architecture.rawValue)-r1".lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return raw.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
            .reduce(into: "") { value, character in
                if character != "-" || value.last != "-" { value.append(character) }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func executableArchitecture(at url: URL) -> RuntimeArchitecture? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]), data.count >= 8 else { return nil }
        let bytes = [UInt8](data.prefix(512))
        let magic = Array(bytes[0..<4])
        if magic == [0xca, 0xfe, 0xba, 0xbe] || magic == [0xbe, 0xba, 0xfe, 0xca] {
            let littleEndian = magic[0] == 0xbe
            func value(at offset: Int) -> UInt32 {
                if littleEndian {
                    return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
                }
                return UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
            }
            let count = min(Int(value(at: 4)), 20)
            var architectures = Set<RuntimeArchitecture>()
            for index in 0..<count {
                let offset = 8 + index * 20
                guard offset + 4 <= bytes.count else { break }
                switch value(at: offset) {
                case 0x01000007: architectures.insert(.x86_64)
                case 0x0100000c: architectures.insert(.arm64)
                default: break
                }
            }
            #if arch(arm64)
            return architectures.contains(.arm64) ? .arm64 : (architectures.contains(.x86_64) ? .x86_64 : nil)
            #else
            return architectures.contains(.x86_64) ? .x86_64 : architectures.first
            #endif
        }
        let littleEndian = magic == [0xcf, 0xfa, 0xed, 0xfe] || magic == [0xce, 0xfa, 0xed, 0xfe]
        let bigEndian = magic == [0xfe, 0xed, 0xfa, 0xcf] || magic == [0xfe, 0xed, 0xfa, 0xce]
        guard littleEndian || bigEndian else { return nil }
        let cpu: UInt32
        if littleEndian {
            cpu = UInt32(bytes[4]) | UInt32(bytes[5]) << 8 | UInt32(bytes[6]) << 16 | UInt32(bytes[7]) << 24
        } else {
            cpu = UInt32(bytes[4]) << 24 | UInt32(bytes[5]) << 16 | UInt32(bytes[6]) << 8 | UInt32(bytes[7])
        }
        switch cpu {
        case 0x01000007: return .x86_64
        case 0x0100000c: return .arm64
        default: return nil
        }
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
