import Foundation

nonisolated enum CompatibilityRating: String, Codable, CaseIterable, Sendable {
    case excellent = "Excellent", good = "Good", limited = "Limited", unknown = "Unknown", unsupported = "Unsupported"

    var symbol: String {
        switch self {
        case .excellent: "checkmark.seal.fill"
        case .good: "checkmark.circle.fill"
        case .limited: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle.fill"
        case .unsupported: "xmark.octagon.fill"
        }
    }
}

nonisolated enum ApplicationStatus: String, Codable, Sendable {
    case ready = "Ready"
    case preparing = "Preparing"
    case starting = "Starting"
    case running = "Running"
    case installing = "Installing"
    case needsAttention = "Needs Attention"
    case unavailable = "Unavailable"

    var isBusy: Bool { self == .preparing || self == .starting || self == .installing }
}

nonisolated struct WindowsApplication: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var publisher: String
    var executablePath: String
    var installerPath: String
    var environmentID: UUID
    var status: ApplicationStatus = .ready
    var compatibility: CompatibilityRating = .unknown
    var windowsVersion = "Windows 11"
    var graphics = "Automatic"
    var storageBytes: Int64 = 0
    var lastOpened: Date?
    var iconSymbol = "app.dashed"
    var lastResult: String?
    var lastExitCode: Int32?
    var lastFailureStage: String?
    var lastErrorDetail: String?
    var storeProvider: GameLibraryProvider?
    var storeExternalID: String?
    var communityCompatibility: CommunityCompatibility?

    var isSteamRuntimeHost: Bool { installerPath == "steam-windows-client" }
}

nonisolated enum GameLibraryProvider: String, Codable, Hashable, CaseIterable, Sendable {
    case steam = "Steam"
    case epic = "Epic Games"
    case gog = "GOG"

    var symbol: String {
        switch self {
        case .steam: "gamecontroller.fill"
        case .epic: "e.square.fill"
        case .gog: "g.square.fill"
        }
    }
}

nonisolated enum StoreGameInstallationPlatform: String, Codable, Hashable, Sendable {
    case windows
    case nativeMacOS
}

nonisolated enum StoreGameSizeSource: String, Codable, Hashable, Sendable {
    case gogManifest
    case epicManifest
    case steamStoreRequirement

    var isExactManifest: Bool { self != .steamStoreRequirement }
}

nonisolated enum StoreExecutableArchitecture: String, Codable, Hashable, Sendable {
    case x86, x86_64

    var displayName: String { self == .x86 ? "32-bit" : "64-bit" }
}

nonisolated enum StoreArchitectureInference {
    static func fromManifest(_ value: Any) -> StoreExecutableArchitecture? {
        var matches = Set<StoreExecutableArchitecture>()
        inspect(value, key: nil, matches: &matches)
        return matches.count == 1 ? matches.first : nil
    }

    static func fromSystemRequirements(_ value: Any?) -> StoreExecutableArchitecture? {
        guard let requirements = value as? [String: Any] else { return nil }
        let text = [requirements["minimum"], requirements["recommended"]]
            .compactMap { $0 as? String }
            .joined(separator: " ")
            .lowercased()
        if text.range(of: #"(?:64[ -]?bit|x86[_-]?64|amd64)"#, options: .regularExpression) != nil { return .x86_64 }
        if text.range(of: #"(?:32[ -]?bit|\bx86\b)"#, options: .regularExpression) != nil { return .x86 }
        return nil
    }

    private static func inspect(_ value: Any, key: String?, matches: inout Set<StoreExecutableArchitecture>) {
        if let dictionary = value as? [String: Any] {
            for (childKey, childValue) in dictionary { inspect(childValue, key: childKey, matches: &matches) }
        } else if let array = value as? [Any] {
            for child in array { inspect(child, key: key, matches: &matches) }
        } else if let string = value as? String {
            let normalizedKey = key?.lowercased() ?? ""
            guard normalizedKey.contains("architecture")
                    || normalizedKey.contains("bitness")
                    || normalizedKey.contains("executable") else { return }
            let normalized = string.lowercased().replacingOccurrences(of: "\\", with: "/")
            if normalized.range(of: #"(?:win64|x86[_-]?64|amd64|64[ -]?bit)"#, options: .regularExpression) != nil { matches.insert(.x86_64) }
            if normalized.range(of: #"(?:win32|32[ -]?bit|(?:^|[/_-])x86(?:[/_.-]|$))"#, options: .regularExpression) != nil { matches.insert(.x86) }
        }
    }
}

nonisolated struct StoreGameSizeEstimate: Codable, Hashable, Sendable {
    var downloadBytes: Int64? = nil
    var installedBytes: Int64? = nil
    var source: StoreGameSizeSource
    var platform: StoreGameInstallationPlatform
    var buildID: String? = nil
    var executableArchitecture: StoreExecutableArchitecture? = nil
    var fetchedAt: Date = .now
}

nonisolated struct StoreRating: Codable, Hashable, Sendable {
    var positivePercent: Int?
    var reviewCount: Int?
    var criticScore: Int?
    var label: String?

    var displayScore: String? {
        if let positivePercent { return "\(positivePercent)% positive" }
        if let criticScore { return "\(criticScore)/100" }
        return label
    }
}

nonisolated struct StoreVideo: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var thumbnailURL: String?
    var videoURL: String
}

nonisolated struct StoreLibraryGame: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var provider: GameLibraryProvider
    var externalID: String
    var name: String
    var developer: String?
    var summary: String?
    var artworkPath: String?
    var portraitImageURL: String?
    var headerImageURL: String?
    var backgroundImageURL: String?
    var screenshotURLs: [String]?
    var videos: [StoreVideo]?
    var storeRating: StoreRating?
    var supportsWindows: Bool?
    var supportsNativeMacOS: Bool?
    var playtimeMinutes: Int = 0
    var lastPlayed: Date?
    var isInstalled = false
    var installPath: String?
    var installedPlatform: StoreGameInstallationPlatform?
    var storageBytes: Int64?
    var sizeEstimate: StoreGameSizeEstimate?
    var compatibility: CommunityCompatibility?
    var currentPlayerCount: Int?

    var displayedStorageBytes: Int64? {
        if let storageBytes, storageBytes > 0 { return storageBytes }
        if let installedBytes = sizeEstimate?.installedBytes, installedBytes > 0 { return installedBytes }
        return nil
    }
}

nonisolated enum CompatibilitySource: String, Codable, Hashable, Sendable {
    case protonDB = "ProtonDB"
    case codeWeavers = "CodeWeavers"
}

nonisolated enum CompatibilityTier: String, Codable, Hashable, Sendable {
    case native, platinum, gold, silver, bronze, borked, pending, unknown
    case runsGreat, runsWell, limitedFunctionality, installsButDoesNotRun, willNotInstall

    var title: String {
        switch self {
        case .runsGreat: "Runs Great"
        case .runsWell: "Runs Well"
        case .limitedFunctionality: "Limited Functionality"
        case .installsButDoesNotRun: "Installs, Will Not Run"
        case .willNotInstall: "Will Not Install"
        default: rawValue.capitalized
        }
    }

    var rating: CompatibilityRating {
        switch self {
        case .native, .platinum, .runsGreat: .excellent
        case .gold, .runsWell: .good
        case .silver, .bronze, .limitedFunctionality: .limited
        case .borked, .installsButDoesNotRun, .willNotInstall: .unsupported
        case .pending, .unknown: .unknown
        }
    }
}

nonisolated struct CommunityCompatibility: Codable, Hashable, Sendable {
    var source: CompatibilitySource
    var tier: CompatibilityTier
    var trendingTier: CompatibilityTier?
    var bestReportedTier: CompatibilityTier?
    var confidence: String?
    var score: Double?
    var reportCount: Int
    var fetchedAt: Date
    var sourceURL: String? = nil
    var platform: String? = nil
    var sourceUpdatedAt: Date? = nil
}

nonisolated enum LibrarySyncState: Equatable, Sendable {
    case idle
    case syncing(GameLibraryProvider)
    case succeeded(GameLibraryProvider, count: Int)
    case failed(GameLibraryProvider, message: String)
}

nonisolated enum EpicConnectionState: Equatable, Sendable {
    case checking
    case supportNotInstalled
    case disconnected
    case preparingSupport
    case authenticating
    case connected(displayName: String?)
    case failed(String)

    var isBusy: Bool {
        self == .checking || self == .preparingSupport || self == .authenticating
    }
}

nonisolated enum GOGConnectionState: Equatable, Sendable {
    case checking
    case supportNotInstalled
    case disconnected
    case preparingSupport
    case authenticating
    case connected(displayName: String?)
    case failed(String)

    var isBusy: Bool {
        self == .checking || self == .preparingSupport || self == .authenticating
    }
}

nonisolated enum StoreGameOperationPhase: String, Codable, Hashable, Sendable {
    case preparing
    case downloading
    case installing
    case verifying

    var title: String {
        switch self {
        case .preparing: "Preparing"
        case .downloading: "Downloading"
        case .installing: "Installing"
        case .verifying: "Verifying"
        }
    }

    var detail: String {
        switch self {
        case .preparing: "Preparing download"
        case .downloading: "Downloading game files"
        case .installing: "Writing game files"
        case .verifying: "Verifying game files"
        }
    }
}

nonisolated struct StoreGameOperationProgress: Codable, Equatable, Sendable {
    var message: String
    var fractionCompleted: Double?
    var startedAt: Date = .now
    var phase: StoreGameOperationPhase = .preparing
    var transferRate: String? = nil
    var transferred: String? = nil
    var total: String? = nil
    // Keep numeric values alongside the helper's display strings. Providers do not
    // consistently use the same units, and the numeric values let the UI calculate
    // a reliable remainder and percentage when only one of those values is logged.
    var transferredBytes: Int64? = nil
    var totalBytes: Int64? = nil
    var estimatedTimeRemaining: String? = nil
    var rawDetail: String? = nil
    var networkBytesPerSecond: Double? = nil
    var diskBytesPerSecond: Double? = nil

    var clampedFraction: Double? {
        if let fractionCompleted {
            return min(max(fractionCompleted, 0), 1)
        }
        guard let transferredBytes, let totalBytes, totalBytes > 0 else { return nil }
        return min(max(Double(transferredBytes) / Double(totalBytes), 0), 1)
    }

    var remainingBytes: Int64? {
        guard let transferredBytes, let totalBytes, totalBytes >= transferredBytes else { return nil }
        return totalBytes - transferredBytes
    }

    static func byteCountString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

nonisolated struct StoreDownloadSample: Codable, Equatable, Sendable, Identifiable {
    var id: Date { timestamp }
    var timestamp: Date
    var networkBytesPerSecond: Double?
    var diskBytesPerSecond: Double?
}

nonisolated struct StoreDownloadRecord: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case downloading
        case paused
        case failed
    }

    var provider: GameLibraryProvider
    var externalID: String
    var destinationRootPath: String
    var platform: StoreGameInstallationPlatform
    var status: Status
    var lastProgress: StoreGameOperationProgress?
    var lastError: String?
    var samples: [StoreDownloadSample]? = nil
    var updatedAt: Date = .now
}

nonisolated enum StoreGameOperationState: Equatable, Sendable {
    case installing(StoreGameOperationProgress)
    case preparingEnvironment(StoreGameOperationProgress)
    case paused(StoreGameOperationProgress, reason: String)
    case awaitingProvider(String)
    case failed(String)

    var progress: StoreGameOperationProgress? {
        switch self {
        case .installing(let value), .preparingEnvironment(let value), .paused(let value, _): value
        case .awaitingProvider, .failed: nil
        }
    }

    var isCancellable: Bool {
        switch self {
        case .installing, .preparingEnvironment: true
        case .paused, .awaitingProvider, .failed: false
        }
    }

    var isResumable: Bool {
        if case .paused = self { return true }
        return false
    }
}

struct WindowsEnvironment: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var windowsVersion = "Windows 11"
    var architecture = "64-bit"
    var runtime = "Boreal Runtime — not installed"
    var graphics = "Automatic"
    var storageBytes: Int64 = 0
    var components: [String] = []
    var createdAt = Date()
    var runtimeID: String?
    var rootPath: String?
    var prefixPath: String?
    var logsPath: String?
}

struct RuntimeDownload: Identifiable, Hashable, Sendable {
    enum State: String, Sendable { case installed = "Installed", available = "Available" }
    let id = UUID()
    var name: String
    var detail: String
    var state: State
    var symbol: String
}

enum InstallationStage: String, CaseIterable, Hashable, Sendable {
    case preparingRuntime
    case creatingEnvironment
    case startingInstaller
    case detectingApplication
    case verifyingFirstLaunch
    case committing

    var title: String {
        switch self {
        case .preparingRuntime: "Preparing runtime"
        case .creatingEnvironment: "Creating Windows environment"
        case .startingInstaller: "Starting installer"
        case .detectingApplication: "Detecting application"
        case .verifyingFirstLaunch: "Verifying first launch"
        case .committing: "Adding to Library"
        }
    }

    var userMessage: String {
        switch self {
        case .preparingRuntime: "Preparing Windows compatibility runtime…"
        case .creatingEnvironment: "Creating Windows environment…"
        case .startingInstaller: "Starting installer…"
        case .detectingApplication: "Detecting installed application…"
        case .verifyingFirstLaunch: "Checking that the application opens correctly…"
        case .committing: "Finishing installation…"
        }
    }
}

struct InstallationProgress: Sendable {
    enum State: Sendable { case idle, installing, succeeded(UUID), failed, cancelled }
    var state: State = .idle
    var stage: InstallationStage?
    var completedStages: Set<InstallationStage> = []
    var failureMessage: String?
    var rollbackCompleted = false
}

struct BorealIssue: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var stage: String
    var recovery: String
    var technicalDetails: String
    var retryApplicationID: UUID?
}

struct RuntimeStatus: Identifiable, Sendable {
    enum Source: Sendable { case installed, catalog }
    enum State: Equatable, Sendable { case loading, available, preparing, installed, needsAttention }
    var id: String
    var name: String
    var wineVersion: String
    var architecture: RuntimeArchitecture
    var compressedSize: Int64?
    var state: State
    var isVerified: Bool
    var detail: String?
    var source: Source
    var origin: RuntimeOrigin? = nil
    var engine: RuntimeEngine = .wine
    var features: RuntimeFeatures? = nil
}

enum RuntimeDiscoveryState: Equatable, Sendable {
    case loading
    case loaded
    case failed(String)
}

struct InstallCandidate: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL
    var name: String { url.deletingPathExtension().lastPathComponent }
    var fileType: String { url.pathExtension.uppercased() }
}

nonisolated enum GameStorage {
    static func allocatedSize(of directory: URL, fileManager: FileManager = .default) -> Int64? {
        guard fileManager.fileExists(atPath: directory.path) else { return nil }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return nil }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total > 0 ? total : nil
    }

    static func availableCapacity(at directory: URL) -> Int64? {
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

enum SidebarDestination: Hashable {
    case library, favorites, accounts, environments, downloads
}

enum LibraryRoute: Hashable {
    case application(UUID)
    case storeGame(UUID)
}
