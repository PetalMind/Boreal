import Foundation
import Darwin

/// Keep the original logical path as an alias: persisted Wine prefixes, runtime
/// manifests and provider configuration can contain absolute paths to it.
nonisolated enum ApplicationDataLocation {
    static let pendingPathKey = "applicationDataPendingPath"
    static let pendingBookmarkKey = "applicationDataPendingBookmark"
    static let bookmarkKey = "applicationDataBookmark"
    private static let backupKey = "applicationDataRelocationBackup"

    static var logicalRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "Boreal", directoryHint: .isDirectory)
    }

    static var currentRoot: URL { logicalRoot.resolvingSymlinksInPath() }

    struct LocationError: LocalizedError {
        let message: String
        var errorDescription: String? { String(localized: String.LocalizationValue(message)) }
    }

    static func schedule(parent: URL, defaults: UserDefaults = .standard) throws {
        let parent = parent.resolvingSymlinksInPath().standardizedFileURL
        let destination = parent.appending(path: "Boreal", directoryHint: .isDirectory)
        try validate(destination: destination, source: currentRoot)
        let bookmark = try parent.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: pendingBookmarkKey)
        defaults.set(destination.path, forKey: pendingPathKey)
    }

    static func cancel(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: pendingPathKey)
        defaults.removeObject(forKey: pendingBookmarkKey)
    }

    private static func validate(destination: URL, source: URL) throws {
        let manager = FileManager.default
        guard destination.path != source.path,
              !destination.path.hasPrefix(source.path + "/"),
              !source.path.hasPrefix(destination.path + "/") else {
            throw LocationError(message: "Choose a folder outside the current Boreal data folder.")
        }
        guard manager.fileExists(atPath: destination.deletingLastPathComponent().path),
              manager.isWritableFile(atPath: destination.deletingLastPathComponent().path) else {
            throw LocationError(message: "The selected disk is unavailable or the folder is not writable.")
        }
        guard !manager.fileExists(atPath: destination.path) else {
            throw LocationError(message: "The selected folder already contains a Boreal folder. Choose another folder to avoid overwriting data.")
        }
    }

    private static func accessBookmark(_ data: Data?) throws {
        guard let data else { return }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        // Access is retained for the process lifetime. Non-sandboxed folders can
        // return false even when normal filesystem access is available.
        _ = url.startAccessingSecurityScopedResource()
    }

    /// Runs before any service opens the library or starts background work.
    static func prepare(defaults: UserDefaults = .standard, root: URL = logicalRoot) throws {
        let manager = FileManager.default
        try accessBookmark(defaults.data(forKey: bookmarkKey))
        // Recover an interruption between renaming the source and creating its alias.
        if let path = defaults.string(forKey: backupKey),
           !manager.fileExists(atPath: root.path), manager.fileExists(atPath: path) {
            try manager.moveItem(at: URL(fileURLWithPath: path), to: root.resolvingSymlinksInPath())
            defaults.removeObject(forKey: backupKey)
        }
        if let path = defaults.string(forKey: pendingPathKey), !path.isEmpty {
            try accessBookmark(defaults.data(forKey: pendingBookmarkKey))
            let destination = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            let source = root.resolvingSymlinksInPath()
            if source.path != destination.path {
                try ensureDataIsIdle(root: root, source: source)
                try validate(destination: destination, source: source)
                let staging = destination.deletingLastPathComponent().appending(path: ".Boreal-moving-\(UUID().uuidString)")
                do {
                    if manager.fileExists(atPath: source.path) {
                        try manager.copyItem(at: source, to: staging)
                    } else {
                        // A dangling alias means the selected disk was disconnected.
                        if (try? manager.destinationOfSymbolicLink(atPath: root.path)) != nil {
                            throw LocationError(message: "Connect the disk containing Boreal data before opening the application.")
                        }
                        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
                    }
                    try manager.moveItem(at: staging, to: destination)
                } catch {
                    try? manager.removeItem(at: staging)
                    throw error
                }
                let backup = source.deletingLastPathComponent().appending(path: ".Boreal-previous-\(UUID().uuidString)")
                let hadSource = manager.fileExists(atPath: source.path)
                let alreadyRedirected = (try? manager.destinationOfSymbolicLink(atPath: root.path)) != nil
                let alias = root.deletingLastPathComponent().appending(path: ".Boreal-alias-\(UUID().uuidString)")
                do {
                    try manager.createSymbolicLink(at: alias, withDestinationURL: destination)
                    if !alreadyRedirected, hadSource {
                        defaults.set(backup.path, forKey: backupKey)
                        guard defaults.synchronize() else {
                            throw LocationError(message: "Boreal couldn’t save the location change. Your data remains in its current folder.")
                        }
                        try manager.moveItem(at: source, to: backup)
                    }
                    // Atomic replacement avoids a dangling alias when changing
                    // between two external disks and never chains old disk paths.
                    guard rename(alias.path, root.path) == 0 else {
                        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                    }
                    if alreadyRedirected { defaults.set(source.path, forKey: backupKey) }
                } catch {
                    try? manager.removeItem(at: alias)
                    if !alreadyRedirected, hadSource, manager.fileExists(atPath: backup.path) {
                        try manager.moveItem(at: backup, to: source)
                    }
                    defaults.removeObject(forKey: backupKey)
                    try? manager.removeItem(at: destination)
                    throw error
                }
            }
            defaults.set(defaults.data(forKey: pendingBookmarkKey), forKey: bookmarkKey)
            cancel(defaults: defaults)
            guard defaults.synchronize() else {
                throw LocationError(message: "Boreal couldn’t save the location change. The previous copy has been preserved.")
            }
        }
        if let path = defaults.string(forKey: backupKey) {
            // Remove the old copy only after the new location and alias are committed.
            if manager.fileExists(atPath: root.path) { try? manager.removeItem(atPath: path) }
            defaults.removeObject(forKey: backupKey)
        }
        if (try? manager.destinationOfSymbolicLink(atPath: root.path)) != nil,
           !manager.fileExists(atPath: root.path) {
            throw LocationError(message: "Connect the disk containing Boreal data before opening the application.")
        }
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        guard manager.isWritableFile(atPath: root.path) else {
            throw LocationError(message: "The Boreal data folder is not writable.")
        }
    }

    private static func ensureDataIsIdle(root: URL, source: URL) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "command="]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LocationError(message: "Boreal couldn’t check whether its data is in use. The location change has been postponed.")
        }
        let commands = String(decoding: data, as: UTF8.self).split(separator: "\n")
        guard !commands.contains(where: { $0.contains(root.path + "/") || $0.contains(source.path + "/") }) else {
            throw LocationError(message: "Close games, Wine processes and installers before moving Boreal data.")
        }
    }
}
