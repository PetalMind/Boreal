import Foundation

nonisolated enum MetricAvailability: String, Codable, Equatable, Sendable {
    case available
    case unavailable
    case unsupported
    case warmingUp

    var isRenderable: Bool { self == .available || self == .warmingUp }
}

nonisolated enum GameMetricSource: String, Codable, Equatable, Sendable {
    case metalHUD
    case wineDebugLog
    case process
    case hostAPI
    case derived
    case unavailable

    var displayName: String {
        switch self {
        case .metalHUD: "Metal HUD"
        case .wineDebugLog: "Wine +fps"
        case .process: "Game process"
        case .hostAPI: "macOS host API"
        case .derived: "Derived"
        case .unavailable: "Unavailable"
        }
    }
}

nonisolated struct MetricsCapabilities: Codable, Equatable, Sendable {
    var fps: MetricAvailability
    var frameTime: MetricAvailability
    var averageFPS: MetricAvailability
    var onePercentLow: MetricAvailability
    var zeroPointOnePercentLow: MetricAvailability
    var p95FrameTime: MetricAvailability
    var p99FrameTime: MetricAvailability
    var gameCPU: MetricAvailability
    var gameMemory: MetricAvailability
    var systemCPU: MetricAvailability
    var systemGPU: MetricAvailability
    var systemMemory: MetricAvailability
    var swap: MetricAvailability
    var gpuMappedMemory: MetricAvailability
    var gpuTemperature: MetricAvailability
    var cpuTemperature: MetricAvailability
    var memoryPressure: MetricAvailability
    var thermalState: MetricAvailability

    init(
        fps: MetricAvailability = .unsupported,
        frameTime: MetricAvailability = .unsupported,
        averageFPS: MetricAvailability = .unsupported,
        onePercentLow: MetricAvailability = .unsupported,
        zeroPointOnePercentLow: MetricAvailability = .unsupported,
        p95FrameTime: MetricAvailability = .unsupported,
        p99FrameTime: MetricAvailability = .unsupported,
        gameCPU: MetricAvailability = .unsupported,
        gameMemory: MetricAvailability = .unsupported,
        systemCPU: MetricAvailability = .unsupported,
        systemGPU: MetricAvailability = .unsupported,
        systemMemory: MetricAvailability = .unsupported,
        swap: MetricAvailability = .unsupported,
        gpuMappedMemory: MetricAvailability = .unsupported,
        gpuTemperature: MetricAvailability = .unsupported,
        cpuTemperature: MetricAvailability = .unsupported,
        memoryPressure: MetricAvailability = .unsupported,
        thermalState: MetricAvailability = .unsupported
    ) {
        self.fps = fps
        self.frameTime = frameTime
        self.averageFPS = averageFPS
        self.onePercentLow = onePercentLow
        self.zeroPointOnePercentLow = zeroPointOnePercentLow
        self.p95FrameTime = p95FrameTime
        self.p99FrameTime = p99FrameTime
        self.gameCPU = gameCPU
        self.gameMemory = gameMemory
        self.systemCPU = systemCPU
        self.systemGPU = systemGPU
        self.systemMemory = systemMemory
        self.swap = swap
        self.gpuMappedMemory = gpuMappedMemory
        self.gpuTemperature = gpuTemperature
        self.cpuTemperature = cpuTemperature
        self.memoryPressure = memoryPressure
        self.thermalState = thermalState
    }

    static let unavailable = MetricsCapabilities()
}

nonisolated enum OverlayMetric: String, CaseIterable, Codable, Hashable, Sendable {
    case fps
    case frameTime
    case onePercentLow
    case zeroPointOnePercentLow
    case p95FrameTime
    case p99FrameTime
    case gameCPU
    case gameMemory
    case systemCPU
    case systemGPU
    case systemMemory
    case swap
    case gpuMappedMemory
    case gpuTemperature
    case cpuTemperature
    case memoryPressure
    case thermalState

    var displayName: String {
        switch self {
        case .fps: "FPS"
        case .frameTime: "Frametime"
        case .onePercentLow: "1% Low"
        case .zeroPointOnePercentLow: "0.1% Low"
        case .p95FrameTime: "P95 frametime"
        case .p99FrameTime: "P99 frametime"
        case .gameCPU: "Game CPU"
        case .gameMemory: "Game memory"
        case .systemCPU: "System CPU"
        case .systemGPU: "System GPU"
        case .systemMemory: "System memory"
        case .swap: "Swap"
        case .gpuMappedMemory: "Driver-mapped memory"
        case .gpuTemperature: "GPU temperature"
        case .cpuTemperature: "CPU temperature"
        case .memoryPressure: "Memory pressure"
        case .thermalState: "Thermal state"
        }
    }

    var group: String {
        switch self {
        case .fps, .frameTime, .onePercentLow, .zeroPointOnePercentLow, .p95FrameTime, .p99FrameTime: "Performance"
        case .gameCPU, .gameMemory: "Game process"
        case .systemCPU, .systemGPU, .systemMemory, .swap, .gpuMappedMemory, .gpuTemperature, .cpuTemperature: "System"
        case .memoryPressure, .thermalState: "Health"
        }
    }

    static let defaultSet: Set<OverlayMetric> = [
        .fps, .frameTime, .onePercentLow,
        .gameCPU, .gameMemory,
        .systemCPU, .systemGPU, .systemMemory, .swap, .gpuMappedMemory,
        .memoryPressure, .thermalState,
    ]

    static var defaultSerialized: String { serialize(defaultSet) }

    static func serialize(_ metrics: Set<OverlayMetric>) -> String {
        allCases.filter(metrics.contains).map(\.rawValue).joined(separator: ",")
    }

    static func deserialize(_ raw: String?) -> Set<OverlayMetric> {
        guard let raw, !raw.isEmpty else { return defaultSet }
        let values = Set(raw.split(separator: ",").compactMap { OverlayMetric(rawValue: String($0)) })
        return values.isEmpty ? defaultSet : values
    }
}

nonisolated struct OverlayGraphicsDescriptor: Codable, Equatable, Sendable {
    var gameAPI: String
    var translator: String
    var hostAPI: String
    var runtime: String

    static let unavailable = OverlayGraphicsDescriptor(gameAPI: "—", translator: "—", hostAPI: "—", runtime: "—")
}

nonisolated struct PerformanceSessionSummary: Codable, Equatable, Sendable {
    var durationSeconds: Double
    var averageFPS: Double?
    var onePercentLowFPS: Double?
    var zeroPointOnePercentLowFPS: Double?
    var p95FrameTimeMilliseconds: Double?
    var p99FrameTimeMilliseconds: Double?
    var peakMemoryBytes: UInt64?
    var seriousThermalDurationSeconds: Double
    var frameCount: Int
    var sampleCount: Int
}

nonisolated struct PerformanceSessionDocument: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let gameID: UUID
    let gameName: String
    let graphics: OverlayGraphicsDescriptor
    let startedAt: Date
    let endedAt: Date
    let samples: [GamePerformanceSample]
    let summary: PerformanceSessionSummary
}

nonisolated struct PerformanceSessionComparison: Codable, Equatable, Sendable {
    let first: PerformanceSessionSummary
    let second: PerformanceSessionSummary
    let averageFPSDelta: Double?
    let onePercentLowFPSDelta: Double?
    let p95FrameTimeDelta: Double?
    let peakMemoryDelta: Int64?

    init(first: PerformanceSessionSummary, second: PerformanceSessionSummary) {
        self.first = first
        self.second = second
        averageFPSDelta = Self.delta(second.averageFPS, first.averageFPS)
        onePercentLowFPSDelta = Self.delta(second.onePercentLowFPS, first.onePercentLowFPS)
        p95FrameTimeDelta = Self.delta(second.p95FrameTimeMilliseconds, first.p95FrameTimeMilliseconds)
        if let first = first.peakMemoryBytes, let second = second.peakMemoryBytes {
            peakMemoryDelta = Int64(clamping: second) - Int64(clamping: first)
        } else {
            peakMemoryDelta = nil
        }
    }

    private static func delta(_ second: Double?, _ first: Double?) -> Double? {
        guard let second, let first else { return nil }
        return second - first
    }
}

/// Stable input for future renderer/runtime benchmark tables. It deliberately
/// references a persisted session instead of treating a one-off overlay value
/// as a benchmark result.
nonisolated struct RendererBenchmarkBaseline: Codable, Equatable, Sendable {
    let sessionID: UUID
    let gameName: String
    let graphics: OverlayGraphicsDescriptor
    let createdAt: Date
    let summary: PerformanceSessionSummary
}

/// Persisted performance log consumed by the overlay export and comparison
/// paths. Keeping this name separate from the live snapshot avoids conflating
/// a single UI value with a complete recorded session.
typealias PerformanceLog = PerformanceSessionDocument
