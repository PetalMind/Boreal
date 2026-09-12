import Compression
import CryptoKit
import Foundation
import Security

// MARK: - Provider-neutral cloud save model

nonisolated enum CloudSavePathSource: String, Codable, Hashable, Sendable {
    case detected
    case manual
}

nonisolated enum CloudSaveDefaults {
    static let namespace = "saves"
}

nonisolated struct CloudSavePathResolution: Codable, Hashable, Sendable {
    let windowsPath: String
    let resolvedURL: URL
    let source: CloudSavePathSource
}

nonisolated struct CloudSaveFile: Codable, Hashable, Identifiable, Sendable {
    let relativePath: String
    let hash: String
    /// Provider-specific fingerprint, such as GOG's MD5 of the gzip payload.
    /// It is kept separate from the local content fingerprint because gzip
    /// implementations can produce different valid byte streams.
    var providerHash: String?
    let modifiedAt: Date?
    let sizeBytes: Int64?

    init(
        relativePath: String,
        hash: String,
        providerHash: String? = nil,
        modifiedAt: Date?,
        sizeBytes: Int64?
    ) {
        self.relativePath = relativePath
        self.hash = hash
        self.providerHash = providerHash
        self.modifiedAt = modifiedAt
        self.sizeBytes = sizeBytes
    }

    var id: String { relativePath }
}

nonisolated struct CloudSaveManifest: Codable, Hashable, Sendable {
    let schemaVersion: Int
    /// The provider product this manifest belongs to. Legacy manifests may not
    /// have this value because it was added after the first implementation.
    let productID: String?
    let generatedAt: Date
    /// Set only after the local and remote listings have converged and the
    /// manifest has been written atomically.
    let lastSuccessfulSync: Date?
    let generation: Int
    let files: [String: CloudSaveFile]

    init(
        schemaVersion: Int = 1,
        productID: String? = nil,
        generatedAt: Date = .now,
        lastSuccessfulSync: Date? = nil,
        generation: Int = 0,
        files: [String: CloudSaveFile]
    ) {
        self.schemaVersion = schemaVersion
        self.productID = productID
        self.generatedAt = generatedAt
        self.lastSuccessfulSync = lastSuccessfulSync
        self.generation = max(0, generation)
        self.files = files
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, productID, generatedAt, lastSuccessfulSync, generation, files
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        productID = try values.decodeIfPresent(String.self, forKey: .productID)
        generatedAt = try values.decode(Date.self, forKey: .generatedAt)
        lastSuccessfulSync = try values.decodeIfPresent(Date.self, forKey: .lastSuccessfulSync)
        generation = max(0, try values.decodeIfPresent(Int.self, forKey: .generation) ?? 0)
        files = try values.decode([String: CloudSaveFile].self, forKey: .files)
    }
}

nonisolated struct CloudSaveSummary: Equatable, Sendable {
    let fileCount: Int
    let totalBytes: Int64
    let latestModification: Date?

    static let empty = CloudSaveSummary(fileCount: 0, totalBytes: 0, latestModification: nil)
}

nonisolated enum CloudSaveSyncState: Equatable, Sendable {
    case unavailable(String)
    case needsConfiguration
    case checking
    case syncing
    case synced
    case conflict
    case failed(String)
}

nonisolated struct CloudSaveStatus: Equatable, Sendable {
    var state: CloudSaveSyncState
    var windowsPath: String?
    var resolvedURL: URL?
    var pathSource: CloudSavePathSource?
    var local: CloudSaveSummary
    var cloud: CloudSaveSummary
    var lastSyncAt: Date?
    var lastUploadedCount: Int
    var lastDownloadedCount: Int
    var lastDeletedCount: Int

    static let unknown = CloudSaveStatus(
        state: .checking,
        windowsPath: nil,
        resolvedURL: nil,
        pathSource: nil,
        local: .empty,
        cloud: .empty,
        lastSyncAt: nil,
        lastUploadedCount: 0,
        lastDownloadedCount: 0,
        lastDeletedCount: 0
    )

    init(
        state: CloudSaveSyncState,
        windowsPath: String? = nil,
        resolvedURL: URL? = nil,
        pathSource: CloudSavePathSource? = nil,
        local: CloudSaveSummary = .empty,
        cloud: CloudSaveSummary = .empty,
        lastSyncAt: Date? = nil,
        lastUploadedCount: Int = 0,
        lastDownloadedCount: Int = 0,
        lastDeletedCount: Int = 0
    ) {
        self.state = state
        self.windowsPath = windowsPath
        self.resolvedURL = resolvedURL
        self.pathSource = pathSource
        self.local = local
        self.cloud = cloud
        self.lastSyncAt = lastSyncAt
        self.lastUploadedCount = lastUploadedCount
        self.lastDownloadedCount = lastDownloadedCount
        self.lastDeletedCount = lastDeletedCount
    }
}

nonisolated enum CloudSaveSyncDirection: String, Equatable, Sendable {
    case automatic
    case useCloud
    case useLocal
}

nonisolated struct GOGCloudAuthorization: Sendable, Hashable {
    let userID: String
    let accessToken: String
    let clientID: String
    let expiresAt: Date?
}

nonisolated protocol GOGCloudAuthorizing: Sendable {
    func cloudAuthorization(for appID: String) async throws -> GOGCloudAuthorization
}

nonisolated protocol CloudSaveProvider: Sendable {
    var provider: GameLibraryProvider { get }

    func availability(for game: StoreLibraryGame) async throws
    func remoteManifest(for game: StoreLibraryGame, namespace: String) async throws -> CloudSaveManifest
    func download(
        _ file: CloudSaveFile,
        for game: StoreLibraryGame,
        namespace: String,
        to destination: URL
    ) async throws
    func upload(
        file: URL,
        relativePath: String,
        modifiedAt: Date?,
        for game: StoreLibraryGame,
        namespace: String
    ) async throws
    func delete(
        _ file: CloudSaveFile,
        for game: StoreLibraryGame,
        namespace: String
    ) async throws
    func commit(for game: StoreLibraryGame, namespace: String) async throws
}

nonisolated enum CloudSaveError: LocalizedError, Sendable {
    case providerUnavailable
    case notAuthenticated
    case invalidConfiguration
    case invalidResponse
    case unsafePath(String)
    case httpStatus(Int, String)
    case transferFailed(String)
    case integrityMismatch(String)
    case conflict(local: CloudSaveSummary, cloud: CloudSaveSummary)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            "Native cloud save support is unavailable for this installation."
        case .notAuthenticated:
            "Connect the GOG account before synchronizing cloud saves."
        case .invalidConfiguration:
            "Choose a valid Windows save location before synchronizing cloud saves."
        case .invalidResponse:
            "GOG returned cloud save data in an unsupported format."
        case .unsafePath(let path):
            "The cloud save path is unsafe: \(path)"
        case .httpStatus(let status, let detail):
            detail.isEmpty
                ? "GOG cloud storage returned HTTP \(status)."
                : "GOG cloud storage returned HTTP \(status): \(detail)"
        case .transferFailed(let detail):
            "Cloud save transfer failed: \(detail)"
        case .integrityMismatch(let path):
            "The downloaded cloud save failed integrity verification: \(path)"
        case .conflict:
            "Boreal could not reconcile the local and GOG cloud saves automatically. Choose which copy to use."
        }
    }
}

nonisolated struct CloudSaveRequest: Sendable {
    let applicationID: UUID
    let game: StoreLibraryGame
    let localDirectory: URL?
    let path: CloudSavePathResolution?
    let namespace: String
}

nonisolated struct CloudSaveSyncResult: Sendable {
    let status: CloudSaveStatus
    let uploadedCount: Int
    let downloadedCount: Int
    let deletedCount: Int
}

// MARK: - Windows save path resolution

nonisolated enum CloudSavePathResolver {
    static func resolve(
        configuredWindowsPath: String?,
        previouslyDetectedWindowsPath: String? = nil,
        gameName: String,
        prefixURL: URL,
        fileManager: FileManager = .default
    ) -> CloudSavePathResolution? {
        if let configuredWindowsPath,
           let resolved = resolveWindowsPath(configuredWindowsPath, prefixURL: prefixURL) {
            return CloudSavePathResolution(
                windowsPath: normalizedWindowsPath(configuredWindowsPath),
                resolvedURL: resolved,
                source: .manual
            )
        }

        // A previously detected path is stronger evidence than a fresh
        // heuristic scan. This avoids changing a user's save location merely
        // because another directory happens to contain a similarly named file.
        if let previouslyDetectedWindowsPath,
           let resolved = resolveWindowsPath(previouslyDetectedWindowsPath, prefixURL: prefixURL),
           isDirectory(resolved, fileManager: fileManager) {
            return CloudSavePathResolution(
                windowsPath: normalizedWindowsPath(previouslyDetectedWindowsPath),
                resolvedURL: resolved,
                source: .detected
            )
        }

        let tokens = normalizedName(gameName)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
        guard !tokens.isEmpty else { return nil }

        let usersURL = prefixURL.appending(path: "drive_c/users", directoryHint: .isDirectory)
        guard let users = try? fileManager.contentsOfDirectory(
            at: usersURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let roots = [
            "Documents",
            "Documents/My Games",
            "Saved Games",
            "AppData/Local",
            "AppData/LocalLow",
            "AppData/Roaming",
        ]
        var matches: [(score: Int, url: URL, windowsPath: String)] = []
        for user in users where isDirectory(user, fileManager: fileManager) {
            for root in roots {
                let rootURL = user.appending(path: root, directoryHint: .isDirectory)
                guard isDirectory(rootURL, fileManager: fileManager) else { continue }
                let candidates = descendants(of: rootURL, maximumDepth: 3, fileManager: fileManager)
                for candidate in candidates where isDirectory(candidate, fileManager: fileManager) {
                    let candidateName = normalizedName(candidate.lastPathComponent)
                    let matchedTokens = tokens.filter { candidateName.contains($0) }.count
                    guard matchedTokens > 0, containsRegularFile(candidate, fileManager: fileManager) else { continue }
                    let score = matchedTokens * 100
                        + (candidateName == normalizedName(gameName) ? 50 : 0)
                        + (root == "Documents" || root == "Documents/My Games" ? 10 : 0)
                    let relative = relativePath(candidate, from: prefixURL)
                    matches.append((score, candidate, windowsPath(forPrefixRelativePath: relative)))
                }
            }
        }

        guard let match = matches.sorted(by: { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
        }).first else { return nil }
        return CloudSavePathResolution(windowsPath: match.windowsPath, resolvedURL: match.url, source: .detected)
    }

    static func resolveWindowsPath(_ path: String, prefixURL: URL) -> URL? {
        let normalized = normalizedWindowsPath(path)
        guard normalized.range(of: #"^C:\\[^:]+$"#, options: .regularExpression) != nil else { return nil }
        let relative = String(normalized.dropFirst(3)).replacingOccurrences(of: "\\", with: "/")
        let components = relative.split(separator: "/").map(String.init)
        guard !components.isEmpty, !components.contains(".."), !components.contains(where: { $0.isEmpty }) else { return nil }
        let value = prefixURL.appending(path: "drive_c").appending(path: components.joined(separator: "/"))
        let root = prefixURL.appending(path: "drive_c", directoryHint: .isDirectory).standardizedFileURL
        let resolved = value.standardizedFileURL
        return resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") ? resolved : nil
    }

    static func normalizedWindowsPath(_ path: String) -> String {
        var value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\"") && value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
        value = value.replacingOccurrences(of: "/", with: "\\")
        while value.hasSuffix("\\") { value.removeLast() }
        return value
    }

    private static let stopWords: Set<String> = ["the", "and", "game", "edition", "complete", "goty"]

    private static func normalizedName(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            && fileManager.fileExists(atPath: url.path)
    }

    private static func descendants(of root: URL, maximumDepth: Int, fileManager: FileManager) -> [URL] {
        guard maximumDepth > 0 else { return [] }
        var result: [URL] = []
        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return result }
        for child in children where isDirectory(child, fileManager: fileManager) {
            result.append(child)
            result.append(contentsOf: descendants(of: child, maximumDepth: maximumDepth - 1, fileManager: fileManager))
        }
        return result
    }

    private static func containsRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        for case let child as URL in enumerator {
            let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values?.isRegularFile == true && values?.isSymbolicLink != true { return true }
        }
        return false
    }

    private static func relativePath(_ url: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        return String(url.standardizedFileURL.path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func windowsPath(forPrefixRelativePath path: String) -> String {
        "C:\\" + path.replacingOccurrences(of: "/", with: "\\")
    }
}

// MARK: - Deterministic gzip compatible with GOG's cloud hash

nonisolated enum GOGCloudCompression {
    enum CompressionError: Error { case failed }

    static func gzip(_ input: Data) throws -> Data {
        let zlib = try encodeZlib(input)
        guard !zlib.isEmpty else { throw CompressionError.failed }
        var result = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03])
        // Apple's COMPRESSION_ZLIB codec exposes the DEFLATE payload without
        // the zlib envelope, so it can be placed directly in a gzip member.
        result.append(zlib)
        appendLittleEndian(crc32(input), to: &result)
        appendLittleEndian(UInt32(truncatingIfNeeded: input.count), to: &result)
        return result
    }

    static func gunzip(_ input: Data) throws -> Data {
        guard input.count >= 18, input[input.startIndex] == 0x1f, input[input.startIndex + 1] == 0x8b else {
            throw CompressionError.failed
        }
        let bytes = [UInt8](input)
        var cursor = 10
        let flags = bytes[3]
        if flags & 0x04 != 0 {
            guard cursor + 2 <= bytes.count else { throw CompressionError.failed }
            let length = Int(bytes[cursor]) | (Int(bytes[cursor + 1]) << 8)
            cursor += 2 + length
        }
        if flags & 0x08 != 0 { cursor = skipZeroTerminated(bytes, from: cursor) }
        if flags & 0x10 != 0 { cursor = skipZeroTerminated(bytes, from: cursor) }
        if flags & 0x02 != 0 { cursor += 2 }
        guard cursor >= 10, cursor + 8 <= bytes.count else { throw CompressionError.failed }
        let rawDeflate = Data(bytes[cursor..<(bytes.count - 8)])
        let expectedCRC = readLittleEndian(bytes, offset: bytes.count - 8)
        let expectedSize = readLittleEndian(bytes, offset: bytes.count - 4)

        if let decoded = tryDecodeZlib(rawDeflate),
           UInt32(truncatingIfNeeded: decoded.count) == expectedSize,
           crc32(decoded) == expectedCRC {
            return decoded
        }
        if let decoded = streamDecodeZlib(rawDeflate),
           UInt32(truncatingIfNeeded: decoded.count) == expectedSize,
           crc32(decoded) == expectedCRC {
            return decoded
        }
        throw CompressionError.failed
    }

    private static func encodeZlib(_ input: Data) throws -> Data {
        var capacity = max(64, input.count + 64)
        for _ in 0..<8 {
            var output = [UInt8](repeating: 0, count: capacity)
            let count = input.withUnsafeBytes { source in
                compression_encode_buffer(
                    &output,
                    capacity,
                    source.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(bitPattern: 1)!,
                    input.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
            if count > 0 { return Data(output.prefix(count)) }
            capacity *= 2
        }
        throw CompressionError.failed
    }

    private static func tryDecodeZlib(_ input: Data) -> Data? {
        var capacity = max(64, input.count * 4)
        for _ in 0..<8 {
            var output = [UInt8](repeating: 0, count: capacity)
            let count = input.withUnsafeBytes { source in
                compression_decode_buffer(
                    &output,
                    capacity,
                    source.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(bitPattern: 1)!,
                    input.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
            if count > 0 { return Data(output.prefix(count)) }
            capacity *= 2
        }
        return nil
    }

    private static func streamDecodeZlib(_ input: Data) -> Data? {
        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!,
            dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!,
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(&stream) }
        var output = Data()
        let chunkSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        return input.withUnsafeBytes { source in
            stream.src_ptr = source.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(bitPattern: 1)!
            stream.src_size = input.count
            while true {
                let status: compression_status = buffer.withUnsafeMutableBufferPointer { destination in
                    stream.dst_ptr = destination.baseAddress ?? UnsafeMutablePointer(bitPattern: 1)!
                    stream.dst_size = destination.count
                    return compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                }
                let produced = buffer.count - stream.dst_size
                if produced > 0 { output.append(contentsOf: buffer.prefix(produced)) }
                if status == COMPRESSION_STATUS_END { return output }
                if status == COMPRESSION_STATUS_ERROR { return output.isEmpty ? nil : output }
                if stream.src_size == 0 && produced == 0 { return output.isEmpty ? nil : output }
            }
        }
    }

    private static func skipZeroTerminated(_ bytes: [UInt8], from start: Int) -> Int {
        var cursor = start
        while cursor < bytes.count, bytes[cursor] != 0 { cursor += 1 }
        return cursor + 1
    }

    private static func appendLittleEndian(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 24))
    }

    private static func readLittleEndian(_ bytes: [UInt8], offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xedb8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var value: UInt32 = 0xffff_ffff
        for byte in data { value = crcTable[Int((value ^ UInt32(byte)) & 0xff)] ^ (value >> 8) }
        return value ^ 0xffff_ffff
    }
}

nonisolated enum GOGCloudMetadataDecoder {
    static func object(from data: Data) -> Any? {
        if let value = try? JSONSerialization.jsonObject(with: data) { return value }
        guard let decoded = try? GOGCloudCompression.gunzip(data) else { return nil }
        return try? JSONSerialization.jsonObject(with: decoded)
    }
}

// MARK: - Keychain

nonisolated enum GOGCredentialKeychain {
    private static let service = "com.boreal.gog"
    private static let account = "refreshToken"

    static func store(refreshToken: String) throws {
        let data = Data(refreshToken.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw KeychainError.unavailable }
        } else if status != errSecSuccess {
            throw KeychainError.unavailable
        }
    }

    static func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError.unavailable }
        return String(data: data, encoding: .utf8)
    }

    static func remove() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unavailable }
    }

    enum KeychainError: Error { case unavailable }
}

// MARK: - Persisted manifest and coordinator

actor CloudSaveCoordinator {
    private let provider: (any CloudSaveProvider)?
    private let manifestRootURL: URL
    private let fileManager: FileManager

    init(
        applicationSupportURL: URL,
        provider: (any CloudSaveProvider)?,
        fileManager: FileManager = .default
    ) {
        self.provider = provider
        self.manifestRootURL = applicationSupportURL.appending(path: "CloudSaves", directoryHint: .isDirectory)
        self.fileManager = fileManager
    }

    func inspect(_ request: CloudSaveRequest) async throws -> CloudSaveStatus {
        guard let provider else { throw CloudSaveError.providerUnavailable }
        guard provider.provider == request.game.provider else { throw CloudSaveError.providerUnavailable }
        guard isSafeManifestComponent(request.game.externalID) else { throw CloudSaveError.invalidConfiguration }
        let remote = try await provider.remoteManifest(for: request.game, namespace: request.namespace)
        let local = try localManifest(at: request.localDirectory)
        let base = loadManifest(for: request.game)
        let decision = classify(local: local.files, remote: remote.files, base: base?.files)
        let state: CloudSaveSyncState
        if request.localDirectory == nil {
            state = .needsConfiguration
        } else if case .conflict = decision {
            state = .conflict
        } else if base != nil, decision.isNone {
            state = .synced
        } else {
            state = .checking
        }
        return status(
            state: state,
            request: request,
            local: local,
            remote: remote,
            base: base,
            lastSyncAt: base?.lastSuccessfulSync ?? base?.generatedAt
        )
    }

    func sync(
        _ request: CloudSaveRequest,
        direction: CloudSaveSyncDirection
    ) async throws -> CloudSaveSyncResult {
        guard let provider else { throw CloudSaveError.providerUnavailable }
        guard provider.provider == request.game.provider else { throw CloudSaveError.providerUnavailable }
        guard isSafeManifestComponent(request.game.externalID) else { throw CloudSaveError.invalidConfiguration }
        guard let localDirectory = request.localDirectory, request.path != nil else {
            throw CloudSaveError.invalidConfiguration
        }

        let local = try localManifest(at: localDirectory)
        let remote = try await provider.remoteManifest(for: request.game, namespace: request.namespace)
        let base = loadManifest(for: request.game)
        let decision = classify(local: local.files, remote: remote.files, base: base?.files)
        if direction == .automatic, case .conflict = decision {
            throw CloudSaveError.conflict(local: summary(local), cloud: summary(remote))
        }

        let localFiles = local.files
        let remoteFiles = remote.files
        let filesToUpload: [CloudSaveFile]
        let filesToDownload: [CloudSaveFile]
        let remoteFilesToDelete: [CloudSaveFile]
        let localPathsToDelete: [String]

        switch direction {
        case .automatic:
            switch decision {
            case .none:
                filesToUpload = []
                filesToDownload = []
                remoteFilesToDelete = []
                localPathsToDelete = []
            case .upload(let upload, let delete):
                filesToUpload = upload
                filesToDownload = []
                remoteFilesToDelete = delete
                localPathsToDelete = []
            case .download(let download, let delete):
                filesToUpload = []
                filesToDownload = download
                remoteFilesToDelete = []
                localPathsToDelete = delete
            case .conflict:
                throw CloudSaveError.conflict(local: summary(local), cloud: summary(remote))
            }
        case .useCloud:
            filesToUpload = []
            filesToDownload = remoteFiles.values.sorted { $0.relativePath < $1.relativePath }
            remoteFilesToDelete = []
            localPathsToDelete = localFiles.keys.filter { remoteFiles[$0] == nil }.sorted()
        case .useLocal:
            filesToUpload = localFiles.values.sorted { $0.relativePath < $1.relativePath }
            filesToDownload = []
            remoteFilesToDelete = remoteFiles.values.filter { localFiles[$0.relativePath] == nil }.sorted { $0.relativePath < $1.relativePath }
            localPathsToDelete = []
        }

        for file in filesToUpload {
            let source = try safeLocalChild(file.relativePath, root: localDirectory)
            try await provider.upload(
                file: source,
                relativePath: file.relativePath,
                modifiedAt: file.modifiedAt,
                for: request.game,
                namespace: request.namespace
            )
        }
        for file in remoteFilesToDelete {
            try await provider.delete(file, for: request.game, namespace: request.namespace)
        }
        for file in filesToDownload {
            let destination = try safeLocalChild(file.relativePath, root: localDirectory)
            try await provider.download(file, for: request.game, namespace: request.namespace, to: destination)
        }
        for relativePath in localPathsToDelete {
            let destination = try safeLocalChild(relativePath, root: localDirectory)
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        }
        let finalLocal = try localManifest(at: localDirectory)
        let finalRemote = try await provider.remoteManifest(for: request.game, namespace: request.namespace)
        guard finalLocal.files.keys == finalRemote.files.keys else {
            throw CloudSaveError.transferFailed("The local and remote file lists did not converge after synchronization.")
        }
        let finalFiles = finalLocal.files.mapValues { file in
            var value = file
            let remoteFile = finalRemote.files[file.relativePath]
            value.providerHash = remoteFile?.providerHash
                ?? (remoteFile?.hash.isEmpty == false ? remoteFile?.hash : nil)
            return value
        }
        let final = CloudSaveManifest(
            productID: request.game.externalID,
            lastSuccessfulSync: .now,
            generation: (base?.generation ?? 0) + 1,
            files: finalFiles
        )
        try saveManifest(final, for: request.game)
        let resultStatus = status(
            state: .synced,
            request: request,
            local: finalLocal,
            remote: finalRemote,
            base: final,
            lastSyncAt: final.lastSuccessfulSync,
            uploadedCount: filesToUpload.count,
            downloadedCount: filesToDownload.count,
            deletedCount: remoteFilesToDelete.count + localPathsToDelete.count
        )
        return CloudSaveSyncResult(
            status: resultStatus,
            uploadedCount: filesToUpload.count,
            downloadedCount: filesToDownload.count,
            deletedCount: remoteFilesToDelete.count + localPathsToDelete.count
        )
    }

    private enum Decision {
        case none
        case upload([CloudSaveFile], [CloudSaveFile])
        case download([CloudSaveFile], [String])
        case conflict

        var isNone: Bool {
            if case .none = self { return true }
            return false
        }
    }

    private func classify(
        local: [String: CloudSaveFile],
        remote: [String: CloudSaveFile],
        base: [String: CloudSaveFile]?
    ) -> Decision {
        if base == nil {
            if local.isEmpty, remote.isEmpty { return .none }
            if local.isEmpty { return .download(remote.values.sorted { $0.relativePath < $1.relativePath }, []) }
            if remote.isEmpty { return .upload(local.values.sorted { $0.relativePath < $1.relativePath }, []) }
            return .conflict
        }
        let base = base!

        // An empty local directory is ambiguous: it can be a wrong path, an
        // unmounted prefix, or a failed save scan. Never turn that observation
        // into a destructive "delete everything in the cloud" operation.
        // Explicit useLocal still remains available when the user confirms it.
        if local.isEmpty,
           !base.isEmpty,
           remote.keys == base.keys,
           base.keys.allSatisfy({ sameRemote(remote[$0], base[$0]) }) {
            return .conflict
        }

        var upload: [CloudSaveFile] = []
        var download: [CloudSaveFile] = []
        var deleteRemote: [CloudSaveFile] = []
        var deleteLocal: [String] = []
        var localChanged = false
        var remoteChanged = false

        for path in Set(local.keys).union(remote.keys).union(base.keys) {
            let localFile = local[path]
            let remoteFile = remote[path]
            let baseFile = base[path]
            let changedLocal = !sameLocal(localFile, baseFile)
            let changedRemote = !sameRemote(remoteFile, baseFile)
            localChanged = localChanged || changedLocal
            remoteChanged = remoteChanged || changedRemote
            if changedLocal && changedRemote { continue }
            if changedLocal {
                if let localFile { upload.append(localFile) } else if let remoteFile { deleteRemote.append(remoteFile) }
            } else if changedRemote {
                if let remoteFile { download.append(remoteFile) } else { deleteLocal.append(path) }
            } else if baseFile == nil {
                if let localFile { upload.append(localFile) } else if let remoteFile { download.append(remoteFile) }
            }
        }
        if localChanged && remoteChanged { return .conflict }
        if upload.isEmpty && deleteRemote.isEmpty && download.isEmpty && deleteLocal.isEmpty { return .none }
        if !upload.isEmpty || !deleteRemote.isEmpty { return .upload(upload, deleteRemote) }
        return .download(download, deleteLocal)
    }

    private func sameLocal(_ lhs: CloudSaveFile?, _ rhs: CloudSaveFile?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): true
        case (.some(let lhs), .some(let rhs)): lhs.hash == rhs.hash
        default: false
        }
    }

    private func sameRemote(_ lhs: CloudSaveFile?, _ rhs: CloudSaveFile?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): true
        case (.some(let lhs), .some(let rhs)): (lhs.providerHash ?? lhs.hash) == (rhs.providerHash ?? rhs.hash)
        default: false
        }
    }

    private func localManifest(at directory: URL?) throws -> CloudSaveManifest {
        guard let directory else { return CloudSaveManifest(files: [:]) }
        if !fileManager.fileExists(atPath: directory.path) { return CloudSaveManifest(files: [:]) }
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return CloudSaveManifest(files: [:]) }
        var files: [String: CloudSaveFile] = [:]
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let relative = String(item.standardizedFileURL.path.dropFirst(directory.standardizedFileURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard isSafeRelativePath(relative) else { throw CloudSaveError.unsafePath(relative) }
            let data = try Data(contentsOf: item)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            files[relative] = CloudSaveFile(relativePath: relative, hash: hash, modifiedAt: values.contentModificationDate, sizeBytes: Int64(values.fileSize ?? data.count))
        }
        return CloudSaveManifest(files: files)
    }

    private func safeLocalChild(_ relativePath: String, root: URL) throws -> URL {
        guard isSafeRelativePath(relativePath) else { throw CloudSaveError.unsafePath(relativePath) }
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = resolvedRoot.appending(path: relativePath).standardizedFileURL
        let resolvedParent = candidate.deletingLastPathComponent().resolvingSymlinksInPath()
        let rootPath = resolvedRoot.path
        guard resolvedParent.path == rootPath || resolvedParent.path.hasPrefix(rootPath + "/") else {
            throw CloudSaveError.unsafePath(relativePath)
        }
        if fileManager.fileExists(atPath: candidate.path),
           (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw CloudSaveError.unsafePath(relativePath)
        }
        return candidate
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.split(separator: "/").contains("..")
    }

    private func isSafeManifestComponent(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
    }

    private func summary(_ manifest: CloudSaveManifest) -> CloudSaveSummary {
        CloudSaveSummary(
            fileCount: manifest.files.count,
            totalBytes: manifest.files.values.compactMap(\.sizeBytes).reduce(0, +),
            latestModification: manifest.files.values.compactMap(\.modifiedAt).max()
        )
    }

    private func status(
        state: CloudSaveSyncState,
        request: CloudSaveRequest,
        local: CloudSaveManifest,
        remote: CloudSaveManifest,
        base: CloudSaveManifest?,
        lastSyncAt: Date?,
        uploadedCount: Int = 0,
        downloadedCount: Int = 0,
        deletedCount: Int = 0
    ) -> CloudSaveStatus {
        CloudSaveStatus(
            state: state,
            windowsPath: request.path?.windowsPath,
            resolvedURL: request.path?.resolvedURL,
            pathSource: request.path?.source,
            local: summary(local),
            cloud: summary(remote),
            lastSyncAt: lastSyncAt ?? base?.generatedAt,
            lastUploadedCount: uploadedCount,
            lastDownloadedCount: downloadedCount,
            lastDeletedCount: deletedCount
        )
    }

    private func loadManifest(for game: StoreLibraryGame) -> CloudSaveManifest? {
        let url = manifestURL(for: game)
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(CloudSaveManifest.self, from: data),
              manifest.schemaVersion <= 1,
              manifest.productID == nil || manifest.productID == game.externalID,
              manifest.files.allSatisfy({ path, file in
                  path == file.relativePath && isSafeRelativePath(path)
              }) else { return nil }
        return manifest
    }

    private func saveManifest(_ manifest: CloudSaveManifest, for game: StoreLibraryGame) throws {
        let url = manifestURL(for: game)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: url, options: .atomic)
    }

    private func manifestURL(for game: StoreLibraryGame) -> URL {
        manifestRootURL
            .appending(path: game.provider.rawValue.lowercased(), directoryHint: .isDirectory)
            .appending(path: game.externalID, directoryHint: .isDirectory)
            .appending(path: "manifest.json")
    }
}

// MARK: - GOG cloud storage

actor GOGCloudSaveProvider: CloudSaveProvider {
    let provider = GameLibraryProvider.gog
    private let authorizer: any GOGCloudAuthorizing
    private let session: URLSession
    private let endpoint = URL(string: "https://cloudstorage.gog.com")!
    // GOG documents the cloud-save model, while this storage endpoint and its
    // wire format mirror the behavior reconstructed in heroic-gogdl. The
    // public docs do not specify these REST details as a supported API.
    private let userAgent = "GOGGalaxyCommunicationService/2.0.13.27 (Windows_32bit) dont_sync_marker/true installation_source/gog"

    init(authorizer: any GOGCloudAuthorizing, session: URLSession = .shared) {
        self.authorizer = authorizer
        self.session = session
    }

    func availability(for game: StoreLibraryGame) async throws {
        _ = try await authorization(for: game)
    }

    func remoteManifest(for game: StoreLibraryGame, namespace: String) async throws -> CloudSaveManifest {
        let authorization = try await authorization(for: game)
        let url = try storageURL(authorization: authorization, game: game, namespace: nil, relativePath: nil)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authorization.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status == 404 { return CloudSaveManifest(productID: game.externalID, files: [:]) }
        guard status == 200 else { throw httpError(status: status, data: data) }
        guard let entries = GOGCloudMetadataDecoder.object(from: data) as? [[String: Any]] else { throw CloudSaveError.invalidResponse }
        let prefix = namespace.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
        var files: [String: CloudSaveFile] = [:]
        for entry in entries {
            guard let name = entry["name"] as? String, name.hasPrefix(prefix), name != namespace,
                  let hash = entry["hash"] as? String, hash != "aadd86936a80ee8a369579c3926f1b3c" else { continue }
            let relative = String(name.dropFirst(prefix.count))
            guard isSafeRelativePath(relative) else { throw CloudSaveError.unsafePath(relative) }
            files[relative] = CloudSaveFile(
                relativePath: relative,
                hash: "",
                providerHash: hash,
                modifiedAt: Self.date(entry["last_modified"]),
                sizeBytes: Self.int64(entry["size"] ?? entry["content_length"])
            )
        }
        return CloudSaveManifest(productID: game.externalID, files: files)
    }

    func download(
        _ file: CloudSaveFile,
        for game: StoreLibraryGame,
        namespace: String,
        to destination: URL
    ) async throws {
        let authorization = try await authorization(for: game)
        let url = try storageURL(authorization: authorization, game: game, namespace: namespace, relativePath: file.relativePath)
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(authorization.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else { throw httpError(status: status, data: data) }
        let expectedProviderHash = file.providerHash ?? file.hash
        let payload: Data
        if md5(data) == expectedProviderHash {
            payload = try GOGCloudCompression.gunzip(data)
        } else if let recompressed = try? GOGCloudCompression.gzip(data), md5(recompressed) == expectedProviderHash {
            payload = try GOGCloudCompression.gunzip(recompressed)
        } else if let httpResponse = response as? HTTPURLResponse,
                  httpResponse.value(forHTTPHeaderField: "Content-Encoding")?.localizedCaseInsensitiveContains("gzip") == true,
                  normalizedETag(httpResponse.value(forHTTPHeaderField: "ETag")) == expectedProviderHash {
            // URLSession may transparently decode a gzip response while the
            // server keeps the original compressed ETag. In that case the
            // HTTPS response plus the matching server ETag is the integrity
            // check available to the native client.
            payload = data
        } else {
            throw CloudSaveError.integrityMismatch(file.relativePath)
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appending(path: ".\(destination.lastPathComponent).boreal-download-\(UUID().uuidString)")
        do {
            try payload.write(to: temporary, options: .atomic)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: temporary, to: destination)
            if let modifiedAt = file.modifiedAt { try? FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: destination.path) }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw CloudSaveError.transferFailed(error.localizedDescription)
        }
    }

    func upload(
        file: URL,
        relativePath: String,
        modifiedAt: Date?,
        for game: StoreLibraryGame,
        namespace: String
    ) async throws {
        guard isSafeRelativePath(relativePath) else { throw CloudSaveError.unsafePath(relativePath) }
        let authorization = try await authorization(for: game)
        let payload: Data
        do { payload = try Data(contentsOf: file) } catch { throw CloudSaveError.transferFailed(error.localizedDescription) }
        let compressed: Data
        do { compressed = try GOGCloudCompression.gzip(payload) } catch { throw CloudSaveError.transferFailed("The save could not be compressed.") }
        let url = try storageURL(authorization: authorization, game: game, namespace: namespace, relativePath: relativePath)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = compressed
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(userAgent, forHTTPHeaderField: "X-Object-Meta-User-Agent")
        request.setValue("Bearer \(authorization.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
        request.setValue(md5(compressed), forHTTPHeaderField: "Etag")
        request.setValue(modifiedAt.map(Self.iso8601String) ?? Self.iso8601String(.now), forHTTPHeaderField: "X-Object-Meta-LocalLastModified")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else { throw httpError(status: status, data: data) }
    }

    func delete(_ file: CloudSaveFile, for game: StoreLibraryGame, namespace: String) async throws {
        let authorization = try await authorization(for: game)
        let url = try storageURL(authorization: authorization, game: game, namespace: namespace, relativePath: file.relativePath)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(authorization.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) || status == 404 else { throw httpError(status: status, data: data) }
    }

    func commit(for game: StoreLibraryGame, namespace: String) async throws {
        // Kept as an explicit provider operation for a future live integration
        // probe. The normal sync path verifies the state with a fresh listing
        // after PUT/DELETE and does not assume the undocumented POST is needed.
        _ = namespace
        let authorization = try await authorization(for: game)
        let url = try storageURL(authorization: authorization, game: game, namespace: nil, relativePath: nil)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(authorization.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else { throw httpError(status: status, data: data) }
    }

    private func authorization(for game: StoreLibraryGame) async throws -> GOGCloudAuthorization {
        do {
            return try await authorizer.cloudAuthorization(for: game.externalID)
        } catch GOGServiceError.notAuthenticated { throw CloudSaveError.notAuthenticated }
        catch { throw error }
    }

    private func storageURL(
        authorization: GOGCloudAuthorization,
        game: StoreLibraryGame,
        namespace: String?,
        relativePath: String?
    ) throws -> URL {
        guard game.provider == .gog,
              !authorization.userID.isEmpty,
              !authorization.clientID.isEmpty,
              authorization.userID.allSatisfy(\.isNumber),
              authorization.clientID.allSatisfy(\.isNumber) else { throw CloudSaveError.invalidConfiguration }
        var components = ["v1", authorization.userID, authorization.clientID]
        if let namespace {
            guard namespace.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else { throw CloudSaveError.invalidConfiguration }
            components.append(namespace)
        }
        if let relativePath {
            guard isSafeRelativePath(relativePath) else { throw CloudSaveError.unsafePath(relativePath) }
            let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
            components.append(contentsOf: relativePath.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) })
        }
        guard let url = URL(string: endpoint.absoluteString + "/" + components.joined(separator: "/")) else { throw CloudSaveError.invalidConfiguration }
        return url
    }

    private func httpError(status: Int, data: Data) -> CloudSaveError {
        let detail = String(data: data.prefix(300), encoding: .utf8) ?? ""
        return .httpStatus(status, detail.replacingOccurrences(of: "\n", with: " "))
    }

    private func md5(_ data: Data) -> String { Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private func normalizedETag(_ value: String?) -> String? {
        guard var value else { return nil }
        if value.hasPrefix("W/") { value.removeFirst(2) }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
    }

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTime]
        return formatter.string(from: date)
    }

    private static func date(_ value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        return ISO8601DateFormatter().date(from: value) ?? {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTime]
            return formatter.date(from: value)
        }()
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.split(separator: "/").contains("..")
    }
}
