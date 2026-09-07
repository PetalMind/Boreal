import CryptoKit
import Foundation

nonisolated struct DirectDrawShimRestoration: Sendable {
    let installedLibrary: URL
    let backupLibrary: URL
    let temporaryLibrary: URL
    let manifestURL: URL
    let originalSHA256: String
    let replacementSHA256: String
}

nonisolated enum DirectDrawCompatibilityError: LocalizedError, Sendable {
    case builtinLibraryMissing(URL)
    case staleInstallation(URL)
    case managedFileModified(URL)
    case unsafeManifestPath(URL)
    case restorationUnavailable(URL)

    var errorDescription: String? {
        switch self {
        case .builtinLibraryMissing(let url):
            "Wine's built-in DirectDraw library is missing at \(url.path)."
        case .staleInstallation(let url):
            "A previous Heroes 3 DirectDraw compatibility repair needs recovery at \(url.path)."
        case .managedFileModified(let url):
            "The Heroes 3 DirectDraw compatibility file was modified outside Boreal at \(url.path)."
        case .unsafeManifestPath(let url):
            "The Heroes 3 DirectDraw compatibility manifest points outside the game directory: \(url.path)"
        case .restorationUnavailable(let url):
            "Boreal cannot restore the original Heroes 3 DirectDraw library at \(url.path)."
        }
    }
}

/// Heroes 3 Complete ships DDrawCompat as `xdd.dll`. That wrapper crashes in
/// the current Wine WoW64 runtime before the game reaches its first frame.
/// Wine's builtin ddraw implementation works, but the game loads a local DLL
/// first, so the replacement must be staged beside the executable. The
/// original file is backed up and restored after the process exits.
nonisolated enum Heroes3DirectDrawCompatibility {
    private struct Manifest: Codable {
        let installedLibrary: URL
        let backupLibrary: URL
        let temporaryLibrary: URL
        let originalSHA256: String
        let replacementSHA256: String
    }

    private static var fileManager: FileManager { .default }

    static func usesWineBuiltinDirectDraw(for executable: URL) -> Bool {
        executable.lastPathComponent.caseInsensitiveCompare("Heroes3.exe") == .orderedSame
    }

    static func prepareIfNeeded(
        executable: URL,
        environment: ManagedBorealEnvironment
    ) throws -> DirectDrawShimRestoration? {
        guard usesWineBuiltinDirectDraw(for: executable) else { return nil }

        let gameDirectory = executable.deletingLastPathComponent().standardizedFileURL
        try recoverStaleInstallation(in: gameDirectory)

        let installedLibrary = gameDirectory.appending(path: "xdd.dll")
        guard fileManager.fileExists(atPath: installedLibrary.path),
              isDDrawCompat(at: installedLibrary) else { return nil }

        let manifestURL = gameDirectory.appending(path: ".boreal-ddraw-shim.json")
        let backupLibrary = gameDirectory.appending(path: ".boreal-xdd-original.dll")
        guard !fileManager.fileExists(atPath: manifestURL.path),
              !fileManager.fileExists(atPath: backupLibrary.path) else {
            throw DirectDrawCompatibilityError.staleInstallation(manifestURL)
        }

        let builtinLibrary = builtinDirectDrawLibrary(for: executable, environment: environment)
        guard fileManager.fileExists(atPath: builtinLibrary.path) else {
            throw DirectDrawCompatibilityError.builtinLibraryMissing(builtinLibrary)
        }

        let temporaryLibrary = gameDirectory.appending(path: ".boreal-xdd-replacement-\(UUID().uuidString).dll")
        let originalSHA256 = try sha256(of: installedLibrary)
        let replacementSHA256 = try sha256(of: builtinLibrary)
        let manifest = Manifest(
            installedLibrary: installedLibrary,
            backupLibrary: backupLibrary,
            temporaryLibrary: temporaryLibrary,
            originalSHA256: originalSHA256,
            replacementSHA256: replacementSHA256
        )

        do {
            try fileManager.copyItem(at: builtinLibrary, to: temporaryLibrary)
            try write(manifest, to: manifestURL)
            try fileManager.moveItem(at: installedLibrary, to: backupLibrary)
            try fileManager.moveItem(at: temporaryLibrary, to: installedLibrary)
            return DirectDrawShimRestoration(
                installedLibrary: installedLibrary,
                backupLibrary: backupLibrary,
                temporaryLibrary: temporaryLibrary,
                manifestURL: manifestURL,
                originalSHA256: originalSHA256,
                replacementSHA256: replacementSHA256
            )
        } catch {
            rollback(manifest: manifest, manifestURL: manifestURL)
            throw error
        }
    }

    static func restore(_ restoration: DirectDrawShimRestoration) throws {
        guard fileManager.fileExists(atPath: restoration.backupLibrary.path) else {
            throw DirectDrawCompatibilityError.restorationUnavailable(restoration.installedLibrary)
        }
        if fileManager.fileExists(atPath: restoration.installedLibrary.path) {
            guard try sha256(of: restoration.installedLibrary) == restoration.replacementSHA256 else {
                throw DirectDrawCompatibilityError.managedFileModified(restoration.installedLibrary)
            }
            try fileManager.removeItem(at: restoration.installedLibrary)
        }
        try fileManager.moveItem(at: restoration.backupLibrary, to: restoration.installedLibrary)
        try? fileManager.removeItem(at: restoration.temporaryLibrary)
        try? fileManager.removeItem(at: restoration.manifestURL)
    }

    private static func recoverStaleInstallation(in gameDirectory: URL) throws {
        let manifestURL = gameDirectory.appending(path: ".boreal-ddraw-shim.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else { return }
        let manifest = try loadManifest(at: manifestURL, gameDirectory: gameDirectory)
        let installedExists = fileManager.fileExists(atPath: manifest.installedLibrary.path)
        let backupExists = fileManager.fileExists(atPath: manifest.backupLibrary.path)

        guard backupExists || installedExists else {
            throw DirectDrawCompatibilityError.restorationUnavailable(manifest.installedLibrary)
        }
        if backupExists {
            if installedExists {
                let installedHash = try sha256(of: manifest.installedLibrary)
                if installedHash == manifest.replacementSHA256 {
                    try fileManager.removeItem(at: manifest.installedLibrary)
                } else if installedHash != manifest.originalSHA256 {
                    throw DirectDrawCompatibilityError.managedFileModified(manifest.installedLibrary)
                }
            }
            if !fileManager.fileExists(atPath: manifest.installedLibrary.path) {
                try fileManager.moveItem(at: manifest.backupLibrary, to: manifest.installedLibrary)
            } else {
                try? fileManager.removeItem(at: manifest.backupLibrary)
            }
        }
        try? fileManager.removeItem(at: manifest.temporaryLibrary)
        try? fileManager.removeItem(at: manifestURL)
    }

    private static func loadManifest(at url: URL, gameDirectory: URL) throws -> Manifest {
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        let paths = [manifest.installedLibrary, manifest.backupLibrary, manifest.temporaryLibrary]
        guard paths.allSatisfy({ $0.standardizedFileURL.deletingLastPathComponent() == gameDirectory }) else {
            throw DirectDrawCompatibilityError.unsafeManifestPath(paths.first { $0.standardizedFileURL.deletingLastPathComponent() != gameDirectory } ?? url)
        }
        return manifest
    }

    private static func write(_ manifest: Manifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: url, options: .atomic)
    }

    private static func rollback(manifest: Manifest, manifestURL: URL) {
        if fileManager.fileExists(atPath: manifest.installedLibrary.path),
           fileManager.fileExists(atPath: manifest.backupLibrary.path) {
            try? fileManager.removeItem(at: manifest.installedLibrary)
        }
        if fileManager.fileExists(atPath: manifest.backupLibrary.path),
           !fileManager.fileExists(atPath: manifest.installedLibrary.path) {
            try? fileManager.moveItem(at: manifest.backupLibrary, to: manifest.installedLibrary)
        }
        try? fileManager.removeItem(at: manifest.temporaryLibrary)
        try? fileManager.removeItem(at: manifestURL)
    }

    private static func builtinDirectDrawLibrary(
        for executable: URL,
        environment: ManagedBorealEnvironment
    ) -> URL {
        let windowsDirectory = environment.prefixURL.appending(path: "drive_c/windows")
        switch WindowsExecutableArchitecture.inspect(executable) {
        case .x86:
            return windowsDirectory.appending(path: "syswow64/ddraw.dll")
        case .x86_64:
            return windowsDirectory.appending(path: "system32/ddraw.dll")
        case .unknown:
            let directory = environment.configuration.architecture == WinePrefixArchitecture.win32.rawValue ? "syswow64" : "system32"
            return windowsDirectory.appending(path: "\(directory)/ddraw.dll")
        }
    }

    private static func isDDrawCompat(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return false }
        let text = String(decoding: data, as: UTF8.self).lowercased()
        return text.contains("ddrawcompat") && !text.contains("wine builtin dll")
    }

    private static func sha256(of url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }
}
