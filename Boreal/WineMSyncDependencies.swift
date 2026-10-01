import Foundation

/// Builds a matching Intel library/header set in a private prefix. Source
/// archives are pinned, retained for provenance and never installed system-wide.
actor WineMSyncDependencies {
    private struct Source {
        let name: String
        let url: String
        let sha256: String
        let arguments: [String]
    }
    private let executor: any ProcessExecuting
    private let session: URLSession
    private let fm = FileManager.default
    private let sources = [
        Source(name: "gmp-6.3.0", url: "https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz", sha256: "a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898", arguments: ["--disable-assembly"]),
        Source(name: "nettle-3.10.2", url: "https://ftp.gnu.org/gnu/nettle/nettle-3.10.2.tar.gz", sha256: "fe9ff51cb1f2abb5e65a6b8c10a92da0ab5ab6eaf26e7fc2b675c45f1fb519b5", arguments: ["--disable-assembler", "--disable-documentation", "--disable-openssl"]),
        Source(name: "gnutls-3.8.13", url: "https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.13.tar.xz", sha256: "ffed8ec1bf09c2426d4f14aae377de4753b53e537d685e604e99a8b16ca9c97e", arguments: ["--with-included-libtasn1", "--with-included-unistring", "--without-p11-kit", "--without-idn", "--without-tpm", "--without-tpm2", "--without-brotli", "--without-zstd", "--disable-libdane", "--disable-cxx", "--disable-tools", "--disable-doc", "--disable-tests", "--disable-nls"]),
        Source(name: "freetype-2.14.3", url: "https://downloads.sourceforge.net/project/freetype/freetype2/2.14.3/freetype-2.14.3.tar.xz", sha256: "36bc4f1cc413335368ee656c42afca65c5a3987e8768cc28cf11ba775e785a5f", arguments: ["--without-harfbuzz", "--without-png", "--without-bzip2", "--without-brotli"])
    ]

    init(executor: any ProcessExecuting, session: URLSession) {
        self.executor = executor
        self.session = session
    }

    func prepare(in prefix: URL, logs: URL, progress: @Sendable (String) async -> Void) async throws -> URL {
        try fm.createDirectory(at: prefix, withIntermediateDirectories: true)
        let archives = prefix.appending(path: "Sources")
        try fm.createDirectory(at: archives, withIntermediateDirectories: true)
        var environment = ProcessInfo.processInfo.environment
        WineProcessEnvironment.removeInheritedRuntimeConfiguration(from: &environment)
        environment["PATH"] = "/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:/usr/local/opt/bison/bin:/usr/local/bin:/usr/bin:/bin"
        environment["CC"] = "/usr/bin/clang -arch x86_64"
        environment["CXX"] = "/usr/bin/clang++ -arch x86_64"
        environment["MACOSX_DEPLOYMENT_TARGET"] = "13.0"
        environment["PKG_CONFIG_LIBDIR"] = prefix.appending(path: "lib/pkgconfig").path
        environment["CPPFLAGS"] = "-I" + prefix.appending(path: "include").path
        environment["LDFLAGS"] = "-L" + prefix.appending(path: "lib").path
        for key in ["PKG_CONFIG_PATH", "SDKROOT", "ARCHFLAGS", "CFLAGS", "CXXFLAGS"] { environment.removeValue(forKey: key) }
        let jobs = min(8, max(1, ProcessInfo.processInfo.activeProcessorCount - 1))
        for source in sources {
            await progress(String(localized: "Preparing Intel library: \(source.name)…"))
            let archive = archives.appending(path: URL(string: source.url)!.lastPathComponent)
            let (temporary, response) = try await session.download(from: URL(string: source.url)!)
            defer { try? fm.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RuntimeManagerError.downloadFailed(source.name) }
            let actual = try RuntimeSecurity.sha256(of: temporary)
            guard actual == source.sha256 else { throw RuntimeManagerError.checksumMismatch(expected: source.sha256, actual: actual) }
            try fm.moveItem(at: temporary, to: archive)
            _ = try await run("extract-" + source.name, "/usr/bin/tar", ["-xf", archive.path, "-C", prefix.path], directory: prefix, environment: environment, logs: logs)
            let sourceDirectory = prefix.appending(path: source.name)
            let directory = prefix.appending(path: "Build/" + source.name)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            _ = try await run("configure-" + source.name, "/bin/sh", [sourceDirectory.appending(path: "configure").path, "--prefix=" + prefix.path, "--host=x86_64-apple-darwin", "--disable-static", "--enable-shared"] + source.arguments, directory: directory, environment: environment, logs: logs)
            _ = try await run("compile-" + source.name, "/usr/bin/make", ["-j\(jobs)"], directory: directory, environment: environment, logs: logs)
            _ = try await run("install-" + source.name, "/usr/bin/make", ["install"], directory: directory, environment: environment, logs: logs)
        }
        let inputs = sources.map { ["name": $0.name, "url": $0.url, "sha256": $0.sha256] }
        try JSONSerialization.data(withJSONObject: inputs, options: [.prettyPrinted, .sortedKeys]).write(to: archives.appending(path: "sources.json"), options: .atomic)
        return prefix
    }

    func bundle(from prefix: URL, into libraries: URL, provenance: URL, logs: URL) async throws {
        try fm.createDirectory(at: libraries, withIntermediateDirectories: true)
        let sourceLibraries = prefix.appending(path: "lib")
        let files = try fm.contentsOfDirectory(at: sourceLibraries, includingPropertiesForKeys: [.isSymbolicLinkKey]).filter { $0.pathExtension == "dylib" }
        var binaries: [URL] = []
        for file in files {
            let destination = libraries.appending(path: file.lastPathComponent)
            if (try file.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true {
                let target = file.resolvingSymlinksInPath()
                guard target.deletingLastPathComponent().path == sourceLibraries.resolvingSymlinksInPath().path else { throw RuntimeManagerError.unsafeArchive(file.path) }
                try fm.createSymbolicLink(atPath: destination.path, withDestinationPath: target.lastPathComponent)
            } else {
                try fm.copyItem(at: file, to: destination)
                binaries.append(destination)
            }
        }
        for binary in binaries {
            _ = try await run("arch-" + binary.lastPathComponent, "/usr/bin/lipo", ["-verify_arch", "x86_64", binary.path], directory: prefix, environment: ProcessInfo.processInfo.environment, logs: logs)
            let result = try await run("links-" + binary.lastPathComponent, "/usr/bin/otool", ["-L", binary.path], directory: prefix, environment: ProcessInfo.processInfo.environment, logs: logs)
            let links = try String(contentsOf: result.stdoutLog, encoding: .utf8).split(separator: "\n").dropFirst().compactMap { $0.components(separatedBy: " (compatibility version").first?.trimmingCharacters(in: .whitespaces) }
            var edits = ["-id", "@loader_path/" + binary.lastPathComponent]
            for link in links {
                if link.hasPrefix(prefix.path + "/") {
                    let name = URL(fileURLWithPath: link).lastPathComponent
                    guard fm.fileExists(atPath: libraries.appending(path: name).path) else { throw RuntimeManagerError.invalidManifest }
                    edits += ["-change", link, "@loader_path/" + name]
                } else if !link.hasPrefix("/usr/lib/") && !link.hasPrefix("/System/Library/") {
                    throw RuntimeManagerError.msyncBuildFailed(String(localized: "Unexpected external dependency: \(link)."))
                }
            }
            _ = try await run("relocate-" + binary.lastPathComponent, "/usr/bin/install_name_tool", edits + [binary.path], directory: prefix, environment: ProcessInfo.processInfo.environment, logs: logs)
            _ = try await run("sign-" + binary.lastPathComponent, "/usr/bin/codesign", ["--force", "--sign", "-", binary.path], directory: prefix, environment: ProcessInfo.processInfo.environment, logs: logs)
        }
        try fm.copyItem(at: prefix.appending(path: "Sources"), to: provenance.appending(path: "Dependencies"))
    }

    private func run(_ stage: String, _ executable: String, _ arguments: [String], directory: URL, environment: [String:String], logs: URL) async throws -> ProcessExecutionResult {
        let receipt = try await executor.launch(ProcessLaunchRequest(executable: URL(fileURLWithPath: executable), arguments: arguments, environment: environment, currentDirectory: directory, stdoutLog: logs.appending(path: "\(stage).stdout.log"), stderrLog: logs.appending(path: "\(stage).stderr.log")))
        let result = try await executor.waitForExit(receipt.id)
        guard result.exitCode == 0 else { throw RuntimeManagerError.msyncBuildFailed(String(localized: "Intel library preparation failed: \(stage). Logs: \(logs.path)")) }
        return result
    }
}
