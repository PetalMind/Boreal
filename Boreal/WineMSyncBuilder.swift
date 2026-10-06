import Foundation

/// Builds an additional local Wine runtime. The recipe and inputs are pinned;
/// installed runtimes and game prefixes are never patched in place.
actor WineMSyncBuilder {
    static let wineVersion = "9.15"
    static let patchRevision = "be7f3e2ff40670018cd7aa9042bad487fa7a83ec"
    private let executor: any ProcessExecuting
    private let session: URLSession
    private let fileManager = FileManager.default

    init(executor: any ProcessExecuting, session: URLSession) {
        self.executor = executor
        self.session = session
    }

    func build(
        in workspace: URL,
        dependencyPrefix requestedPrefix: URL?,
        logs: URL,
        progress: @Sendable (String) async -> Void
    ) async throws -> URL {
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logs, withIntermediateDirectories: true)
        try String(localized: "Checking build requirements.").write(to: logs.appending(path: "preflight.log"), atomically: true, encoding: .utf8)
        var environment = ProcessInfo.processInfo.environment
        WineProcessEnvironment.removeInheritedRuntimeConfiguration(from: &environment)
        let searchPaths = [
            (requestedPrefix ?? URL(fileURLWithPath: "/usr/local")).appending(path: "opt/bison/bin").path,
            (requestedPrefix ?? URL(fileURLWithPath: "/usr/local")).appending(path: "bin").path,
            "/opt/homebrew/opt/bison/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"
        ]
        environment["PATH"] = searchPaths.joined(separator: ":")
        environment["CC"] = "/usr/bin/clang -arch x86_64"
        environment["CXX"] = "/usr/bin/clang++ -arch x86_64"
        environment["MACOSX_DEPLOYMENT_TARGET"] = "13.0"
        environment.removeValue(forKey: "PKG_CONFIG_PATH")
        for key in ["CFLAGS", "CXXFLAGS", "CPPFLAGS", "LDFLAGS", "SDKROOT", "ARCHFLAGS"] {
            environment.removeValue(forKey: key)
        }
        // Wine 9.15 uses identifiers such as `bool` that became keywords in C23.
        // Its configure script applies CROSSCFLAGS to both Windows architectures.
        environment["CROSSCFLAGS"] = "-g -O2 -std=gnu17"
        await progress(String(localized: "Checking Wine build tools and x86_64 libraries…"))
        let requiredTools = ["bison", "flex", "make", "pkg-config", "x86_64-w64-mingw32-gcc", "i686-w64-mingw32-gcc"]
        let missingTools = requiredTools.filter { name in
            !searchPaths.contains { fileManager.isExecutableFile(atPath: URL(fileURLWithPath: $0).appending(path: name).path) }
        }
        guard missingTools.isEmpty else {
            throw failure(String(localized: "Missing Wine build tools: \(missingTools.joined(separator: ", ")). Install them before starting the build."), logs: logs)
        }
        try await run("developer-tools", executable: "/usr/bin/xcrun", arguments: ["--find", "clang"], directory: workspace, environment: environment, logs: logs)
        #if arch(arm64)
        try await run("rosetta", executable: "/usr/bin/arch", arguments: ["-x86_64", "/usr/bin/true"], directory: workspace, environment: environment, logs: logs)
        #endif
        let dependencies = WineMSyncDependencies(executor: executor, session: session)
        let dependencyPrefix: URL
        if let requestedPrefix {
            dependencyPrefix = requestedPrefix
            environment["PKG_CONFIG_LIBDIR"] = ["lib/pkgconfig", "share/pkgconfig"]
                .map { dependencyPrefix.appending(path: $0).path }.joined(separator: ":")
        } else {
            dependencyPrefix = try await dependencies.prepare(in: workspace.appending(path: "Dependencies"), logs: logs, progress: progress)
            environment["PKG_CONFIG_LIBDIR"] = dependencyPrefix.appending(path: "lib/pkgconfig").path
        }
        for library in ["libfreetype.dylib", "libgnutls.dylib"] {
            let url = dependencyPrefix.appending(path: "lib/\(library)")
            guard fileManager.isReadableFile(atPath: url.path) else {
                throw failure(String(localized: "Missing x86_64 build library: \(url.path). Select the directory containing Intel FreeType and GnuTLS."), logs: logs)
            }
            try await run("check-\(library)", executable: "/usr/bin/lipo", arguments: ["-verify_arch", "x86_64", url.path], directory: workspace, environment: environment, logs: logs)
        }

        let sourceArchive = workspace.appending(path: "wine-9.15.tar.gz")
        let patch = workspace.appending(path: "msync-devel.patch")
        await progress(String(localized: "Downloading and verifying Wine 9.15 sources…"))
        try await download(
            "https://codeload.github.com/wine-mirror/wine/tar.gz/refs/tags/wine-9.15",
            sha256: "735c34c446fe00439d22f42eca9dec91acc0aed3b5164260fc726e03ad8bc60e",
            to: sourceArchive
        )
        await progress(String(localized: "Downloading and verifying the MSync patch…"))
        try await download(
            "https://raw.githubusercontent.com/marzent/wine-msync/\(Self.patchRevision)/msync-devel.patch",
            sha256: "ba20515c8c89b2035f887d2131b22f67222598ea2cd3ffa0219b31df4a67453b",
            to: patch
        )
        try await run("extract", executable: "/usr/bin/tar", arguments: ["-xzf", sourceArchive.path, "-C", workspace.path], directory: workspace, environment: environment, logs: logs)
        let source = workspace.appending(path: "wine-wine-9.15", directoryHint: .isDirectory)
        await progress(String(localized: "Checking and applying MSync to Wine sources…"))
        let patchArguments = ["--batch", "--forward", "--fuzz=0", "-p1", "-i", patch.path]
        try await run("patch-check", executable: "/usr/bin/patch", arguments: ["--dry-run"] + patchArguments, directory: source, environment: environment, logs: logs)
        try await run("patch", executable: "/usr/bin/patch", arguments: patchArguments, directory: source, environment: environment, logs: logs)

        // Newer binutils make .idata read-only. Backport Wine's paired fixes
        // so delay-load IAT writes use .data and negative IAT offsets stay valid.
        let compatibilityPatches = [
            (revision: "fd59962827a715d321f91c9bdb43f3e61f9ebbcb", name: "signed-delay-iat", sha256: "44a51734ef42fe88d9a0ff9a743a4884306de69f26d594d778cf7c15627e749f"),
            (revision: "c9519f68ea04915a60704534ab3afec5ec1b8fd7", name: "writable-delay-imports", sha256: "e4d98232241b01beea4f5608ccee1233533d9be8482bff0e91c8d8286b0911ef")
        ]
        var compatibilityInputs: [URL] = []
        for fix in compatibilityPatches {
            let input = workspace.appending(path: fix.name + ".patch")
            try await download("https://github.com/wine-mirror/wine/commit/\(fix.revision).patch", sha256: fix.sha256, to: input)
            let arguments = ["--batch", "--forward", "--fuzz=0", "-p1", "-i", input.path]
            try await run("patch-check-" + fix.name, executable: "/usr/bin/patch", arguments: ["--dry-run"] + arguments, directory: source, environment: environment, logs: logs)
            try await run("patch-" + fix.name, executable: "/usr/bin/patch", arguments: arguments, directory: source, environment: environment, logs: logs)
            compatibilityInputs.append(input)
        }

        let build = workspace.appending(path: "Build", directoryHint: .isDirectory)
        let install = workspace.appending(path: "Install", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: build, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: install, withIntermediateDirectories: true)
        await progress(String(localized: "Configuring Wine with MSync and WoW64…"))
        try await run("configure", executable: "/bin/sh", arguments: [
            source.appending(path: "configure").path,
            "--prefix=/boreal-msync", "--host=x86_64-apple-darwin", "--enable-win64", "--enable-archs=i386,x86_64",
            "--with-mingw", "--with-freetype", "--with-gnutls", "--without-x", "--without-gstreamer"
        ], directory: build, environment: environment, logs: logs)
        await progress(String(localized: "Compiling Wine with MSync. This can take a long time…"))
        let jobs = min(8, max(1, ProcessInfo.processInfo.activeProcessorCount - 1))
        try await run("compile", executable: "/usr/bin/make", arguments: ["-j\(jobs)"], directory: build, environment: environment, logs: logs)
        await progress(String(localized: "Packaging the compiled Wine runtime…"))
        try await run("install", executable: "/usr/bin/make", arguments: ["install", "DESTDIR=\(install.path)"], directory: build, environment: environment, logs: logs)
        let app = workspace.appending(path: "Wine-MSync.app", directoryHint: .isDirectory)
        let resources = app.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
        try fileManager.moveItem(at: install.appending(path: "boreal-msync"), to: resources.appending(path: "wine"))
        let info: [String: String] = [
            "CFBundleName": "Wine MSync", "CFBundleDisplayName": "Wine MSync",
            "CFBundleIdentifier": "local.boreal.wine-msync", "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": Self.wineVersion, "LSMinimumSystemVersion": "13.0"
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appending(path: "Contents/Info.plist"), options: .atomic)
        // Keep corresponding upstream sources and modifications with the
        // snapshot, including upstream license text in the source archive.
        let provenance = resources.appending(path: "MSync-Sources", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: provenance, withIntermediateDirectories: true)
        if requestedPrefix == nil {
            try await dependencies.bundle(from: dependencyPrefix, into: resources.appending(path: "wine/lib"), provenance: provenance, logs: logs)
        }
        for input in [sourceArchive, patch] + compatibilityInputs {
            try fileManager.copyItem(at: input, to: provenance.appending(path: input.lastPathComponent))
        }
        let receipt: [String: String] = [
            "wineVersion": Self.wineVersion, "msyncRevision": Self.patchRevision,
            "compatibilityRevisions": compatibilityPatches.map(\.revision).joined(separator: ","),
            "dependencyPrefix": dependencyPrefix.path,
            "sourceProject": "https://github.com/wine-mirror/wine",
            "patchProject": "https://github.com/marzent/wine-msync",
            "license": "LGPL-2.1", "buildLogs": logs.path
        ]
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            .write(to: provenance.appending(path: "build.json"), options: .atomic)
        return app
    }

    private func download(_ address: String, sha256: String, to destination: URL) async throws {
        let (temporary, response) = try await session.download(from: URL(string: address)!)
        defer { try? fileManager.removeItem(at: temporary) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw RuntimeManagerError.downloadFailed(address)
        }
        let actual = try RuntimeSecurity.sha256(of: temporary)
        guard actual == sha256 else { throw RuntimeManagerError.checksumMismatch(expected: sha256, actual: actual) }
        try fileManager.moveItem(at: temporary, to: destination)
    }

    private func run(_ stage: String, executable: String, arguments: [String], directory: URL, environment: [String: String], logs: URL) async throws {
        let request = ProcessLaunchRequest(
            executable: URL(fileURLWithPath: executable), arguments: arguments,
            environment: environment, currentDirectory: directory,
            stdoutLog: logs.appending(path: "\(stage).stdout.log"),
            stderrLog: logs.appending(path: "\(stage).stderr.log")
        )
        let receipt = try await executor.launch(request)
        let result = try await executor.waitForExit(receipt.id)
        guard result.exitCode == 0 else {
            throw failure(String(localized: "Wine MSync preparation failed at stage: \(stage) (exit code \(result.exitCode))."), logs: logs)
        }
    }

    private func failure(_ reason: String, logs: URL) -> RuntimeManagerError {
        try? reason.write(to: logs.appending(path: "failure.log"), atomically: true, encoding: .utf8)
        return .msyncBuildFailed(reason + "\n" + String(localized: "Build logs: \(logs.path)"))
    }
}
