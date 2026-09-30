import Foundation

nonisolated enum GTAIVModAdapter {
    static let knownExecutables: Set<String> = ["gtaiv.exe", "launchgtaiv.exe", "eflc.exe"]

    static func supports(game: StoreLibraryGame) -> Bool {
        let name = game.name.lowercased()
        return name.contains("grand theft auto iv")
            || name.contains("gta iv")
            || (game.provider == .steam && game.externalID == "12210")
    }

    static func gameRoot(
        installationRoot: URL?,
        executable: URL?,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [URL] = []
        if let executable {
            var current = executable.standardizedFileURL.deletingLastPathComponent()
            for _ in 0..<7 {
                candidates.append(current)
                if current.path == "/" { break }
                current.deleteLastPathComponent()
            }
        }
        if let installationRoot {
            var current = installationRoot.standardizedFileURL
            if current.pathExtension.caseInsensitiveCompare("exe") == .orderedSame {
                current.deleteLastPathComponent()
            }
            for _ in 0..<5 {
                candidates.append(current)
                if current.path == "/" { break }
                current.deleteLastPathComponent()
            }
        }

        var seen = Set<String>()
        return candidates.first { candidate in
            seen.insert(candidate.path).inserted
                && isGameRoot(candidate, fileManager: fileManager)
        }
    }

    static func isGameRoot(_ root: URL, fileManager: FileManager = .default) -> Bool {
        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        return children.contains { child in
            guard knownExecutables.contains(child.lastPathComponent.lowercased()),
                  let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
            return values.isRegularFile == true && values.isSymbolicLink != true
        }
    }
}

nonisolated enum GTAIVXLiveLessStatus: Sendable, Equatable {
    case checking
    case unavailable
    case notInstalled
    case installed
    case missingFile
    case externallyModified
    case invalidReceipt
}

nonisolated struct GTAIVXLiveLessInstaller: Sendable {
    static let archiveURL = URL(string: "https://public.sannybuilder.com/GTA4/xliveless-1.0a4.rar")!

    let applicationSupportURL: URL

    func status(gameID: UUID, gameRoot: URL) -> GTAIVXLiveLessStatus {
        let managerDirectory = gameDataURL(for: gameID)
        let receiptURL = receiptURL(for: gameID)
        guard FileManager.default.fileExists(atPath: receiptURL.path) else { return .notInstalled }

        do {
            let receipt = try readReceipt(at: receiptURL)
            guard receipt.version == 1,
                  receipt.originalFileExisted == (receipt.backupFilename != nil),
                  receipt.originalFileExisted == (receipt.originalSHA256 != nil) else { return .invalidReceipt }
            if receipt.originalFileExisted {
                guard let backupFilename = receipt.backupFilename,
                      isSafeFilename(backupFilename) else { return .invalidReceipt }
                let backupURL = managerDirectory.appending(path: backupFilename)
                guard FileManager.default.fileExists(atPath: backupURL.path),
                      let originalSHA256 = receipt.originalSHA256,
                      try RuntimeSecurity.sha256(of: backupURL) == originalSHA256 else { return .invalidReceipt }
            }
            guard let target = try existingXLiveFile(in: gameRoot) else { return .missingFile }
            return try RuntimeSecurity.sha256(of: target) == receipt.installedSHA256
                ? .installed
                : .externallyModified
        } catch {
            return .invalidReceipt
        }
    }

    func install(gameID: UUID, gameRoot: URL) async throws {
        guard GTAIVModAdapter.isGameRoot(gameRoot) else { throw GTAIVXLiveLessError.gameFolderUnavailable }

        let (downloadURL, response) = try await URLSession.shared.download(from: Self.archiveURL)
        defer { try? FileManager.default.removeItem(at: downloadURL) }
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              http.url?.scheme?.lowercased() == "https" else {
            throw GTAIVXLiveLessError.downloadRejected
        }

        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "boreal-xliveless-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let archive = temporaryRoot.appending(path: "xliveless.rar")
        try FileManager.default.copyItem(at: downloadURL, to: archive)
        let archiveManager = GTASAModManager(applicationSupportURL: applicationSupportURL)
        let format = try archiveManager.archiveFormat(for: archive)
        guard format == .rar else { throw GTAIVXLiveLessError.downloadRejected }
        let extractedRoot = try archiveManager.extract(archive, format: format)
        defer { try? FileManager.default.removeItem(at: extractedRoot) }

        let payloads = try archiveManager.contentFiles(in: extractedRoot).filter {
            $0.lastPathComponent.caseInsensitiveCompare("xlive.dll") == .orderedSame
        }
        guard payloads.count == 1, let payload = payloads.first else {
            throw GTAIVXLiveLessError.payloadNotFound
        }
        try validateDLL(at: payload)

        try installPayload(payload, gameID: gameID, gameRoot: gameRoot)
    }

    func restoreOriginal(gameID: UUID, gameRoot: URL) throws {
        guard GTAIVModAdapter.isGameRoot(gameRoot) else { throw GTAIVXLiveLessError.gameFolderUnavailable }
        switch status(gameID: gameID, gameRoot: gameRoot) {
        case .installed: break
        case .missingFile: throw GTAIVXLiveLessError.installedFileMissing
        case .invalidReceipt: throw GTAIVXLiveLessError.originalBackupUnavailable
        default: throw GTAIVXLiveLessError.managedFileChanged
        }
        let managerDirectory = gameDataURL(for: gameID)
        let receipt = try readReceipt(at: receiptURL(for: gameID))
        guard let target = try existingXLiveFile(in: gameRoot) else { throw GTAIVXLiveLessError.installedFileMissing }
        guard try RuntimeSecurity.sha256(of: target) == receipt.installedSHA256 else {
            throw GTAIVXLiveLessError.managedFileChanged
        }

        let fileManager = FileManager.default
        let rollbackURL = gameRoot.appending(path: ".boreal-xlive-rollback-\(UUID().uuidString)")
        var stagedOriginal: URL?
        if receipt.originalFileExisted {
            guard let backupFilename = receipt.backupFilename, isSafeFilename(backupFilename) else {
                throw GTAIVXLiveLessError.originalBackupUnavailable
            }
            let backupURL = managerDirectory.appending(path: backupFilename)
            guard fileManager.fileExists(atPath: backupURL.path),
                  try RuntimeSecurity.sha256(of: backupURL) == receipt.originalSHA256 else {
                throw GTAIVXLiveLessError.originalBackupUnavailable
            }
            let staged = gameRoot.appending(path: ".boreal-xlive-restore-\(UUID().uuidString)")
            try fileManager.copyItem(at: backupURL, to: staged)
            stagedOriginal = staged
        }

        do {
            try fileManager.moveItem(at: target, to: rollbackURL)
            if let stagedOriginal {
                try fileManager.moveItem(at: stagedOriginal, to: gameRoot.appending(path: target.lastPathComponent))
            }
            try fileManager.removeItem(at: receiptURL(for: gameID))
        } catch {
            if fileManager.fileExists(atPath: target.path) { try? fileManager.removeItem(at: target) }
            if fileManager.fileExists(atPath: rollbackURL.path) { try? fileManager.moveItem(at: rollbackURL, to: target) }
            if let stagedOriginal { try? fileManager.removeItem(at: stagedOriginal) }
            throw error
        }

        try? fileManager.removeItem(at: rollbackURL)
        if let backupFilename = receipt.backupFilename {
            try? fileManager.removeItem(at: managerDirectory.appending(path: backupFilename))
        }
    }

    private func installPayload(_ payload: URL, gameID: UUID, gameRoot: URL) throws {
        let fileManager = FileManager.default
        let managerDirectory = gameDataURL(for: gameID)
        let receiptFile = receiptURL(for: gameID)
        try fileManager.createDirectory(at: managerDirectory, withIntermediateDirectories: true)

        let currentTarget = try existingXLiveFile(in: gameRoot)
        let oldReceipt: GTAIVXLiveLessReceipt?
        if fileManager.fileExists(atPath: receiptFile.path) {
            oldReceipt = try readReceipt(at: receiptFile)
            let currentStatus = status(gameID: gameID, gameRoot: gameRoot)
            guard currentStatus == .installed || currentStatus == .missingFile else {
                throw GTAIVXLiveLessError.managedFileChanged
            }
            if let oldReceipt, oldReceipt.originalFileExisted {
                guard let backupFilename = oldReceipt.backupFilename,
                      isSafeFilename(backupFilename),
                      let originalSHA256 = oldReceipt.originalSHA256 else {
                    throw GTAIVXLiveLessError.originalBackupUnavailable
                }
                let backupURL = managerDirectory.appending(path: backupFilename)
                guard
                      fileManager.fileExists(atPath: backupURL.path),
                      try RuntimeSecurity.sha256(of: backupURL) == originalSHA256 else {
                    throw GTAIVXLiveLessError.originalBackupUnavailable
                }
            }
        } else {
            oldReceipt = nil
        }

        var originalExisted = oldReceipt?.originalFileExisted ?? false
        var backupFilename = oldReceipt?.backupFilename
        var originalSHA256 = oldReceipt?.originalSHA256
        if oldReceipt == nil, let currentTarget {
            let backup = "original-xlive-\(UUID().uuidString).dll"
            let backupURL = managerDirectory.appending(path: backup)
            try fileManager.copyItem(at: currentTarget, to: backupURL)
            backupFilename = backup
            originalSHA256 = try RuntimeSecurity.sha256(of: backupURL)
            originalExisted = true
        }

        let target = currentTarget ?? gameRoot.appending(path: "xlive.dll")
        let staged = gameRoot.appending(path: ".boreal-xlive-stage-\(UUID().uuidString).dll")
        let rollback = gameRoot.appending(path: ".boreal-xlive-rollback-\(UUID().uuidString)")
        try fileManager.copyItem(at: payload, to: staged)
        let hadTarget = fileManager.fileExists(atPath: target.path)
        do {
            if hadTarget { try fileManager.moveItem(at: target, to: rollback) }
            try fileManager.moveItem(at: staged, to: target)
            let receipt = GTAIVXLiveLessReceipt(
                version: 1,
                installedSHA256: try RuntimeSecurity.sha256(of: target),
                originalFileExisted: originalExisted,
                originalSHA256: originalSHA256,
                backupFilename: backupFilename
            )
            try saveReceipt(receipt, to: receiptFile)
        } catch {
            if fileManager.fileExists(atPath: target.path) { try? fileManager.removeItem(at: target) }
            if hadTarget, fileManager.fileExists(atPath: rollback.path) { try? fileManager.moveItem(at: rollback, to: target) }
            if fileManager.fileExists(atPath: staged.path) { try? fileManager.removeItem(at: staged) }
            throw error
        }
        try? fileManager.removeItem(at: rollback)
    }

    private func validateDLL(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              (512...(64 * 1024 * 1024)).contains(size) else {
            throw GTAIVXLiveLessError.payloadInvalid
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 0x40,
              data[0] == 0x4D,
              data[1] == 0x5A else { throw GTAIVXLiveLessError.payloadInvalid }
        let peOffset = Int(data[0x3C])
            | (Int(data[0x3D]) << 8)
            | (Int(data[0x3E]) << 16)
            | (Int(data[0x3F]) << 24)
        guard peOffset >= 0x40,
              peOffset <= data.count - 4,
              data[peOffset] == 0x50,
              data[peOffset + 1] == 0x45,
              data[peOffset + 2] == 0,
              data[peOffset + 3] == 0,
              peOffset <= data.count - 6,
              data[peOffset + 4] == 0x4C,
              data[peOffset + 5] == 0x01 else { throw GTAIVXLiveLessError.payloadInvalid }
    }

    private func existingXLiveFile(in gameRoot: URL) throws -> URL? {
        let fileManager = FileManager.default
        let children = try fileManager.contentsOfDirectory(
            at: gameRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        guard let target = children.first(where: {
            $0.lastPathComponent.caseInsensitiveCompare("xlive.dll") == .orderedSame
        }) else { return nil }
        guard children.filter({
            $0.lastPathComponent.caseInsensitiveCompare("xlive.dll") == .orderedSame
        }).count == 1 else {
            throw GTAIVXLiveLessError.unsafeTarget
        }
        let values = try target.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw GTAIVXLiveLessError.unsafeTarget
        }
        return target
    }

    private func gameDataURL(for gameID: UUID) -> URL {
        applicationSupportURL
            .appending(path: "Mods/GTAIVXLiveLess", directoryHint: .isDirectory)
            .appending(path: gameID.uuidString, directoryHint: .isDirectory)
    }

    private func receiptURL(for gameID: UUID) -> URL {
        gameDataURL(for: gameID).appending(path: "installation.json")
    }

    private func readReceipt(at url: URL) throws -> GTAIVXLiveLessReceipt {
        try JSONDecoder().decode(GTAIVXLiveLessReceipt.self, from: Data(contentsOf: url))
    }

    private func saveReceipt(_ receipt: GTAIVXLiveLessReceipt, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(receipt).write(to: url, options: .atomic)
    }

    private func isSafeFilename(_ value: String) -> Bool {
        !value.isEmpty
            && URL(fileURLWithPath: value).lastPathComponent == value
            && !value.contains("/")
            && !value.contains("\\")
    }
}

private nonisolated struct GTAIVXLiveLessReceipt: Codable, Sendable {
    let version: Int
    let installedSHA256: String
    let originalFileExisted: Bool
    let originalSHA256: String?
    let backupFilename: String?
}

nonisolated enum GTAIVXLiveLessError: LocalizedError, Sendable {
    case gameFolderUnavailable
    case gameActive
    case downloadRejected
    case payloadNotFound
    case payloadInvalid
    case unsafeTarget
    case installedFileMissing
    case managedFileChanged
    case originalBackupUnavailable

    var errorDescription: String? {
        switch self {
        case .gameFolderUnavailable:
            "The installed GTA IV game folder could not be identified."
        case .gameActive:
            "Close GTA IV before installing or removing XLiveLess."
        case .downloadRejected:
            "The XLiveLess download was not accepted as a secure archive."
        case .payloadNotFound:
            "The archive did not contain exactly one xlive.dll file."
        case .payloadInvalid:
            "The downloaded xlive.dll is not a valid Windows PE library."
        case .unsafeTarget:
            "The existing xlive.dll is not a regular file. Boreal left it untouched."
        case .installedFileMissing:
            "The installed xlive.dll is missing."
        case .managedFileChanged:
            "xlive.dll changed outside Boreal after installation. Boreal left it untouched."
        case .originalBackupUnavailable:
            "The original xlive.dll backup is missing or changed, so Boreal cannot safely continue."
        }
    }
}
