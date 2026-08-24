import Foundation

enum CompatibilityRating: String, Codable, CaseIterable, Sendable {
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

enum ApplicationStatus: String, Codable, Sendable {
    case ready = "Ready"
    case preparing = "Preparing"
    case starting = "Starting"
    case running = "Running"
    case installing = "Installing"
    case needsAttention = "Needs Attention"
    case unavailable = "Unavailable"

    var isBusy: Bool { self == .preparing || self == .starting || self == .installing }
}

struct WindowsApplication: Identifiable, Codable, Hashable, Sendable {
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
    var compatibility: CommunityCompatibility?
}

nonisolated enum CompatibilitySource: String, Codable, Hashable, Sendable {
    case protonDB = "ProtonDB"
}

nonisolated enum CompatibilityTier: String, Codable, Hashable, Sendable {
    case native, platinum, gold, silver, bronze, borked, pending, unknown

    var title: String { rawValue.capitalized }

    var rating: CompatibilityRating {
        switch self {
        case .native, .platinum: .excellent
        case .gold: .good
        case .silver, .bronze: .limited
        case .borked: .unsupported
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

nonisolated enum StoreGameOperationState: Equatable, Sendable {
    case installing
    case preparingEnvironment
    case failed(String)
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
    enum State: Sendable { case idle, installing, succeeded(UUID), failed }
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

enum SidebarDestination: Hashable {
    case library, accounts, environments, downloads
    case application(UUID)
    case storeGame(UUID)
}
