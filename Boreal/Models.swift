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

nonisolated enum WineWindowsVersion: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case windows11 = "win11"
    case windows10 = "win10"
    case windows81 = "win81"
    case windows8 = "win8"
    case windows7 = "win7"
    case windowsXP = "winxp"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .windows11: "Windows 11"
        case .windows10: "Windows 10"
        case .windows81: "Windows 8.1"
        case .windows8: "Windows 8"
        case .windows7: "Windows 7"
        case .windowsXP: "Windows XP"
        }
    }
}

nonisolated enum WinePrefixArchitecture: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case win64
    case win32

    var id: String { rawValue }
    var displayName: String { self == .win64 ? "64-bit (Win64)" : "32-bit (Win32)" }
}

nonisolated enum WineGraphicsBackend: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case automatic
    case d3dMetal
    case dxmt
    case dxvk
    case wineD3D

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .d3dMetal: "D3DMetal"
        case .dxmt: "DXMT"
        case .dxvk: "DXVK"
        case .wineD3D: "Wine (WineD3D)"
        }
    }
    var detail: String {
        switch self {
        case .automatic: "Chooses the best renderer actually supplied by the selected runtime."
        case .d3dMetal: "Apple Game Porting Toolkit renderer, optimized for DirectX 11 and 12."
        case .dxmt: "Metal-based Direct3D 11 translation. Requires a runtime package containing DXMT."
        case .dxvk: "Vulkan-based Direct3D 10–11 translation using the managed macOS package. Direct3D 9 uses WineD3D."
        case .wineD3D: "Wine's built-in OpenGL renderer and the safest fallback."
        }
    }
    var requiredEngine: RuntimeEngine? {
        switch self {
        case .automatic: nil
        case .d3dMetal: .gamePortingToolkit
        case .dxmt, .dxvk, .wineD3D: .wine
        }
    }
}

nonisolated enum LegacyGraphicsWrapper: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case none
    case dgVoodoo2

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none: "Disabled"
        case .dgVoodoo2: "dgVoodoo2"
        }
    }
}

/// The legacy API is selected explicitly in the first implementation. Boreal
/// does not guess from a filename and never installs every wrapper DLL.
nonisolated enum LegacyGraphicsAPI: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case directDraw
    case direct3D8
    case direct3D9

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .directDraw: "DirectDraw / Direct3D 1–7"
        case .direct3D8: "Direct3D 8"
        case .direct3D9: "Direct3D 9"
        }
    }

    var libraryName: String {
        switch self {
        case .directDraw: "ddraw"
        case .direct3D8: "d3d8"
        case .direct3D9: "d3d9"
        }
    }
}

nonisolated enum DLLOverrideMode: String, Codable, Sendable, Hashable {
    case nativeThenBuiltin

    var wineValue: String {
        switch self {
        case .nativeThenBuiltin: "n,b"
        }
    }
}

nonisolated struct DLLOverride: Codable, Sendable, Hashable {
    var library: String
    var mode: DLLOverrideMode
}

nonisolated enum GraphicsAPI: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case automatic
    case directX9
    case directX10
    case directX11
    case directX12

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .directX9: "DirectX 9"
        case .directX10: "DirectX 10"
        case .directX11: "DirectX 11"
        case .directX12: "DirectX 12"
        }
    }
}

nonisolated struct GraphicsAPILaunchOption: Codable, Hashable, Sendable {
    var api: GraphicsAPI
    var arguments: [String] = []
    var executable: String? = nil
}

nonisolated struct GameGraphicsProfile: Codable, Hashable, Sendable {
    var provider: GameLibraryProvider
    var externalID: String
    var availableAPIs: [GraphicsAPI]
    var defaultAPI: GraphicsAPI
    var launchOptions: [GraphicsAPILaunchOption]
    var preferredBackend: WineGraphicsBackend? = nil

    func launchOption(for api: GraphicsAPI) -> GraphicsAPILaunchOption? {
        launchOptions.first { $0.api == api }
    }
}

nonisolated enum AuxiliaryExecutableRole: String, Codable, Hashable, Sendable {
    case configuration
    case launcher
    case benchmark
    case alternate
    case tool

    var displayName: String {
        switch self {
        case .configuration: "Configure"
        case .launcher: "Run Launcher"
        case .benchmark: "Run Benchmark"
        case .alternate: "Run Alternate Executable"
        case .tool: "Run Tool"
        }
    }

    var symbol: String {
        switch self {
        case .configuration: "gearshape"
        case .launcher: "play.rectangle"
        case .benchmark: "gauge.with.dots.needle.67percent"
        case .alternate: "arrow.triangle.branch"
        case .tool: "wrench.and.screwdriver"
        }
    }
}

/// A secondary entry point that belongs to the same installed game and must
/// run in that game's managed Windows environment.
nonisolated struct AuxiliaryExecutable: Codable, Hashable, Sendable, Identifiable {
    var executablePath: String
    var role: AuxiliaryExecutableRole
    var displayName: String

    var id: String { executablePath.lowercased() }
}

nonisolated struct WineCompatibilityProfile: Codable, Hashable, Sendable {
    var windowsVersion: WineWindowsVersion = .windows11
    var architecture: WinePrefixArchitecture = .win64
    var graphicsBackend: WineGraphicsBackend = .automatic
    var legacyWrapper: LegacyGraphicsWrapper = .none
    var legacyGraphicsAPI: LegacyGraphicsAPI = .directDraw
    var graphicsAPI: GraphicsAPI? = nil
    var esyncEnabled = true
    var msyncEnabled = true
    var retinaModeEnabled = true
    var fullscreenFSREnabled = false
    var overlayCompatibleFullscreen = true
    /// Selected CoreGraphics display ID for the Wine desktop; nil follows the main display.
    var overlayDisplayID: UInt32? = nil
    var debugLoggingEnabled = false
    var disableSteamInputEquivalent = false
    var forceXInput = true
    var launchArguments = ""

    private enum CodingKeys: String, CodingKey {
        case windowsVersion, architecture, graphicsBackend, legacyWrapper, legacyGraphicsAPI, graphicsAPI
        case esyncEnabled, msyncEnabled, retinaModeEnabled, fullscreenFSREnabled, overlayCompatibleFullscreen, overlayDisplayID, debugLoggingEnabled
        case disableSteamInputEquivalent, forceXInput, launchArguments
    }

    static let `default` = WineCompatibilityProfile()

    var parsedLaunchArguments: [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for character in launchArguments {
            if escaped {
                if character == "\\" || character == "\"" || character == "'" || character.isWhitespace {
                    current.append(character)
                } else {
                    current.append("\\")
                    current.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if let activeQuote = quote {
                if character == activeQuote { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

extension WineCompatibilityProfile {
    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        windowsVersion = try values.decodeIfPresent(WineWindowsVersion.self, forKey: .windowsVersion) ?? .windows11
        architecture = try values.decodeIfPresent(WinePrefixArchitecture.self, forKey: .architecture) ?? .win64
        graphicsBackend = try values.decodeIfPresent(WineGraphicsBackend.self, forKey: .graphicsBackend) ?? .automatic
        legacyWrapper = try values.decodeIfPresent(LegacyGraphicsWrapper.self, forKey: .legacyWrapper) ?? .none
        legacyGraphicsAPI = try values.decodeIfPresent(LegacyGraphicsAPI.self, forKey: .legacyGraphicsAPI) ?? .directDraw
        graphicsAPI = try values.decodeIfPresent(GraphicsAPI.self, forKey: .graphicsAPI)
        esyncEnabled = try values.decodeIfPresent(Bool.self, forKey: .esyncEnabled) ?? true
        msyncEnabled = try values.decodeIfPresent(Bool.self, forKey: .msyncEnabled) ?? true
        retinaModeEnabled = try values.decodeIfPresent(Bool.self, forKey: .retinaModeEnabled) ?? true
        fullscreenFSREnabled = try values.decodeIfPresent(Bool.self, forKey: .fullscreenFSREnabled) ?? false
        overlayCompatibleFullscreen = try values.decodeIfPresent(Bool.self, forKey: .overlayCompatibleFullscreen) ?? true
        overlayDisplayID = try values.decodeIfPresent(UInt32.self, forKey: .overlayDisplayID)
        debugLoggingEnabled = try values.decodeIfPresent(Bool.self, forKey: .debugLoggingEnabled) ?? false
        disableSteamInputEquivalent = try values.decodeIfPresent(Bool.self, forKey: .disableSteamInputEquivalent) ?? false
        forceXInput = try values.decodeIfPresent(Bool.self, forKey: .forceXInput) ?? true
        launchArguments = try values.decodeIfPresent(String.self, forKey: .launchArguments) ?? ""
    }
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
    /// True when the linked store record supplies presentation metadata only.
    /// Boreal still launches the imported executable directly.
    var storeMetadataOnly: Bool? = nil
    var communityCompatibility: CommunityCompatibility?
    var compatibilityProfile: WineCompatibilityProfile?
    /// Optional keeps library files written by older Boreal builds decodable.
    var auxiliaryExecutables: [AuxiliaryExecutable]?

    var isSteamRuntimeHost: Bool { installerPath == "steam-windows-client" }
    var usesStoreMetadataOnly: Bool { storeMetadataOnly == true }
    var usesSharedSteamEnvironment: Bool {
        (storeProvider == .steam && !usesStoreMetadataOnly) || isSteamRuntimeHost
    }
    var resolvedAuxiliaryExecutables: [AuxiliaryExecutable] { auxiliaryExecutables ?? [] }
    var resolvedCompatibilityProfile: WineCompatibilityProfile {
        compatibilityProfile ?? WineCompatibilityProfile(
            windowsVersion: WineWindowsVersion.allCases.first(where: { $0.displayName == windowsVersion }) ?? .windows11,
            architecture: .win64,
            graphicsBackend: graphics == RuntimeEngine.gamePortingToolkit.graphicsName ? .d3dMetal : (graphics == RuntimeEngine.wine.graphicsName ? .wineD3D : .automatic)
        )
    }
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

nonisolated struct GamePlaySession: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var startedAt: Date
    var endedAt: Date?
    /// Accumulated from ContinuousClock checkpoints while Boreal is alive.
    /// Optional keeps sessions written by the first implementation decodable.
    var measuredDurationSeconds: TimeInterval?
    var lastCheckpointAt: Date?

    var isActive: Bool { endedAt == nil }
    var duration: TimeInterval {
        if let measuredDurationSeconds { return max(0, measuredDurationSeconds) }
        guard let endedAt else { return 0 }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }

    mutating func checkpoint(elapsed: TimeInterval, at date: Date) {
        measuredDurationSeconds = duration + max(0, elapsed)
        lastCheckpointAt = date
    }

    mutating func finish(at date: Date) {
        endedAt = max(date, startedAt)
        lastCheckpointAt = endedAt
    }
}

nonisolated struct GameActivityDay: Identifiable, Hashable, Sendable {
    var date: Date
    var duration: TimeInterval
    var id: Date { date }
}

nonisolated struct GameActivityStatistics: Hashable, Sendable {
    var thisWeek: TimeInterval
    var lastWeek: TimeInterval
    var averageSession: TimeInterval
    var longestSession: TimeInterval
    var days: [GameActivityDay]

    init(
        sessions: [GamePlaySession],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        heatmapDayCount: Int = 84
    ) {
        let validSessions = sessions.filter { $0.duration > 0 }
        let thisWeekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
        let lastWeekDate = thisWeekInterval?.start.addingTimeInterval(-1)
        let lastWeekInterval = lastWeekDate.flatMap { calendar.dateInterval(of: .weekOfYear, for: $0) }
        thisWeek = validSessions
            .filter { thisWeekInterval?.contains($0.startedAt) == true }
            .reduce(0) { $0 + $1.duration }
        lastWeek = validSessions
            .filter { lastWeekInterval?.contains($0.startedAt) == true }
            .reduce(0) { $0 + $1.duration }
        let total = validSessions.reduce(0) { $0 + $1.duration }
        averageSession = validSessions.isEmpty ? 0 : total / Double(validSessions.count)
        longestSession = validSessions.map(\.duration).max() ?? 0

        let today = calendar.startOfDay(for: now)
        let count = max(1, heatmapDayCount)
        let firstDay = calendar.date(byAdding: .day, value: -(count - 1), to: today) ?? today
        var durationByDay: [Date: TimeInterval] = [:]
        for session in validSessions {
            var cursor = session.startedAt
            var remaining = session.duration
            while remaining > 0 {
                let day = calendar.startOfDay(for: cursor)
                let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? cursor.addingTimeInterval(86_400)
                let slice = min(remaining, max(0.001, nextDay.timeIntervalSince(cursor)))
                durationByDay[day, default: 0] += slice
                remaining -= slice
                cursor = nextDay
            }
        }
        days = (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: firstDay).map {
                GameActivityDay(date: $0, duration: durationByDay[$0, default: 0])
            }
        }
    }
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
    /// Time reported by the store provider. It deliberately excludes Boreal's
    /// local timer so a later provider sync cannot double-count a session.
    var playtimeMinutes: Int = 0
    var lastPlayed: Date?
    /// Sessions measured from the managed Wine/GPTK environment rather than
    /// imported from a store. Optional keeps older library files decodable.
    var borealPlaytimeSeconds: TimeInterval?
    var playSessions: [GamePlaySession]?
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

    var measuredPlaytime: TimeInterval { max(0, borealPlaytimeSeconds ?? 0) }
    var resolvedPlaySessions: [GamePlaySession] {
        (playSessions ?? []).sorted { $0.startedAt > $1.startedAt }
    }
    var completedPlaySessions: [GamePlaySession] { resolvedPlaySessions.filter { !$0.isActive } }
    var activePlaySession: GamePlaySession? { resolvedPlaySessions.first(where: \.isActive) }

    mutating func appendPlaySession(_ session: GamePlaySession) {
        var recordedSessions = playSessions ?? []
        recordedSessions.append(session)
        playSessions = recordedSessions
    }

    mutating func updatePlaySession(_ session: GamePlaySession) {
        guard var recordedSessions = playSessions,
              let index = recordedSessions.firstIndex(where: { $0.id == session.id }) else { return }
        recordedSessions[index] = session
        playSessions = recordedSessions
        borealPlaytimeSeconds = recordedSessions.reduce(0) { $0 + $1.duration }
        if let endedAt = session.endedAt { lastPlayed = endedAt }
    }

    mutating func preserveMeasuredActivity(from existing: StoreLibraryGame) {
        borealPlaytimeSeconds = existing.borealPlaytimeSeconds
        playSessions = existing.playSessions
        playtimeMinutes = max(playtimeMinutes, existing.playtimeMinutes)
        if let existingLastPlayed = existing.lastPlayed {
            lastPlayed = max(lastPlayed ?? .distantPast, existingLastPlayed)
        }
    }
}

nonisolated enum CompatibilitySource: String, Codable, Hashable, Sendable {
    case protonDB = "ProtonDB"
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
