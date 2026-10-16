import Foundation
import CryptoKit

nonisolated enum GraphicsBackendStatus: String, Codable, Hashable, Sendable {
    case recommended, compatible, fallback, notApplicable, unavailable, failedInitialization

    var title: String {
        switch self {
        case .recommended: String(localized: "Recommended")
        case .compatible: String(localized: "Compatible")
        case .fallback: String(localized: "Fallback")
        case .notApplicable: String(localized: "Not applicable")
        case .unavailable: String(localized: "Unavailable")
        case .failedInitialization: String(localized: "Failed initialization")
        }
    }
}

/// Results are scoped to actual executable, runtime and component identities.
/// A changed component or runtime cannot inherit an older initialization failure.
nonisolated struct GraphicsCompatibilityKey: Codable, Hashable, Sendable {
    let executableSHA256: String
    let runtimeID: String
    let runtimeVersion: String
    let runtimeFingerprint: String
    let backend: GraphicsBackend
    let componentIdentity: String
    let executableArchitecture: WindowsExecutableArchitecture
    let prefixArchitecture: WinePrefixArchitecture
    let api: GraphicsAPI
    let legacyWrapper: LegacyGraphicsWrapper
    let wineD3DRenderer: WineD3DRenderer
}

nonisolated struct GraphicsCompatibilityResult: Codable, Hashable, Sendable {
    enum Outcome: String, Codable, Sendable { case failedInitialization, processObserved }
    let key: GraphicsCompatibilityKey
    let outcome: Outcome
    let date: Date
    let logReference: URL?
}

nonisolated struct GraphicsBackendAssessment: Codable, Hashable, Sendable, Identifiable {
    let backend: GraphicsBackend
    let status: GraphicsBackendStatus
    let reasons: [String]
    let componentVersion: String?
    let compatibilityKey: GraphicsCompatibilityKey?
    var id: GraphicsBackend { backend }
}

nonisolated struct GraphicsResolutionReport: Codable, Hashable, Sendable {
    let requestedBackend: GraphicsBackend
    let detectedAPI: DirectXDetectionResult
    let effectiveAPI: GraphicsAPI
    let apiReason: String
    let executableArchitecture: WindowsExecutableArchitecture
    let prefixArchitecture: WinePrefixArchitecture
    let runtimeID: String
    let runtimeName: String
    let runtimeVersion: String
    let legacyWrapper: LegacyGraphicsWrapper
    let selected: GraphicsStackResolution
    let rankedCandidates: [GraphicsStackResolution]
    let assessments: [GraphicsBackendAssessment]
    let automaticFallbackAllowed: Bool

    var fallbackPlan: [GraphicsStackResolution] {
        guard automaticFallbackAllowed, selected.isAvailable else { return [] }
        return rankedCandidates.filter { $0.stack.backend != selected.stack.backend }
    }

    func key(for backend: GraphicsBackend) -> GraphicsCompatibilityKey? {
        assessments.first { $0.backend == backend }?.compatibilityKey
    }

    static func make(
        executable: URL,
        profile: WineCompatibilityProfile,
        gameProfile: GameGraphicsProfile?,
        runtime: InstalledRuntime,
        architecture: WinePrefixArchitecture,
        componentReferences: [GraphicsComponentReference] = [],
        learnedResults: [GraphicsCompatibilityResult] = [],
        attemptedBackends: Set<GraphicsBackend> = [],
        executableSHA256: String? = nil
    ) -> GraphicsResolutionReport {
        let detected = GraphicsAPIDetector.analyze(executable: executable)
        let api = CompatibilityPreparationResolver.directXAPI(
            executable: executable, userProfile: profile, gameProfile: gameProfile
        )
        let executableArchitecture = WindowsExecutableArchitecture.inspect(executable)
        let executablePrefix: WinePrefixArchitecture? = switch executableArchitecture {
        case .x86: .win32
        case .x86_64: .win64
        default: nil
        }
        let ranked = GraphicsBackendResolver.rankedCandidates(
            api: api, gameProfile: gameProfile, runtime: runtime,
            architecture: architecture, executableArchitecture: executablePrefix,
            fallback: profile.graphicsFallback
        )
        let initial = GraphicsBackendResolver.resolve(
            api: api, requestedBackend: profile.graphicsBackend,
            gameProfile: gameProfile, runtime: runtime, architecture: architecture,
            executableArchitecture: executablePrefix, fallback: profile.graphicsFallback
        )
        let automatic = profile.graphicsBackend == .automatic && gameProfile?.enforcedBackend == nil
        let digest = executableSHA256
        let componentStore = GraphicsComponentStore(rootURL: runtime.rootURL
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "Components"))
        var keys: [GraphicsBackend: GraphicsCompatibilityKey] = [:]
        var versions: [GraphicsBackend: String] = [:]
        for stack in GraphicsStackCatalog.all {
            let component = stack.requiredComponents.first
            let inventory = runtime.graphicsComponents?.first { $0.backend == stack.backend }
            let reference = component.flatMap { component in
                componentReferences.first { $0.component == component }
                    ?? inventory?.reference ?? componentStore.reference(for: component)
            }
            let version = reference?.version ?? inventory?.version
            versions[stack.backend] = version
            // Bundled components without a receipt/version have no safe cache
            // identity. They still participate in this launch's fallback plan.
            let identity = reference.map { $0.version + ":" + $0.sha256 }
                ?? version.map { "bundle:" + $0 }
                ?? (component == nil ? "builtin:" + runtime.wineVersion : nil)
            if let digest, let identity {
                keys[stack.backend] = GraphicsCompatibilityKey(
                    executableSHA256: digest, runtimeID: runtime.id,
                    runtimeVersion: runtime.wineVersion,
                    runtimeFingerprint: runtime.baseIdentity?.hostSHA256 ?? runtime.rootURL.standardizedFileURL.path,
                    backend: stack.backend, componentIdentity: identity,
                    executableArchitecture: executableArchitecture, prefixArchitecture: architecture,
                    api: api, legacyWrapper: gameProfile?.enforcedLegacyWrapper ?? profile.legacyWrapper,
                    wineD3DRenderer: profile.wineD3DRenderer
                )
            }
        }
        let failed = Set(keys.compactMap { backend, key -> GraphicsBackend? in
            let latest = learnedResults.filter { $0.key == key }.max { $0.date < $1.date }
            return latest?.outcome == .failedInitialization ? backend : nil
        })
        let candidates = automatic ? ranked.filter {
            !failed.contains($0.stack.backend) && !attemptedBackends.contains($0.stack.backend)
        } : ranked
        let selected: GraphicsStackResolution
        if automatic {
            selected = candidates.first ?? GraphicsStackResolution(
                stack: initial.stack, score: -1_000,
                reasons: ["No untried compatible graphics backend remains. Review graphics details or clear learned results."]
            )
        } else {
            selected = initial
        }
        let assessments = GraphicsStackCatalog.all.map { stack in
            let status: GraphicsBackendStatus
            let reasons: [String]
            if !stack.supports(api: api, architecture: architecture)
                || !(executablePrefix.map(stack.supportedArchitectures.contains) ?? true) {
                status = .notApplicable
                reasons = ["\(stack.backend.displayName) does not support \(api.displayName) with this architecture."]
            } else if automatic && (failed.contains(stack.backend) || attemptedBackends.contains(stack.backend)) {
                status = .failedInitialization
                reasons = ["Initialization failed for this executable, runtime and component version."]
            } else if let candidate = ranked.first(where: { $0.stack.backend == stack.backend }) {
                status = selected.isAvailable && selected.stack.backend == stack.backend ? .recommended
                    : (stack.backend == .wineD3D && api != .openGL ? .fallback : .compatible)
                reasons = candidate.reasons
            } else {
                status = .unavailable
                reasons = ["The selected runtime does not provide the required verified graphics capability or component."]
            }
            return GraphicsBackendAssessment(
                backend: stack.backend, status: status, reasons: reasons,
                componentVersion: versions[stack.backend], compatibilityKey: keys[stack.backend]
            )
        }
        let apiReason: String
        if let manual = profile.graphicsAPI, manual != .automatic { apiReason = "Explicit graphics API selection" }
        else if profile.legacyWrapper != .none || gameProfile?.enforcedLegacyWrapper != nil { apiReason = "Renderer consumes the legacy wrapper's output API" }
        else if gameProfile?.enforcedAPI != nil || gameProfile?.defaultAPI != nil { apiReason = "Known game graphics profile" }
        else if detected.api != nil { apiReason = "Graphics API detected from the executable" }
        else { apiReason = "Graphics API is unknown or ambiguous; all detected candidates remain in the evidence" }
        return GraphicsResolutionReport(
            requestedBackend: profile.graphicsBackend, detectedAPI: detected, effectiveAPI: api,
            apiReason: apiReason, executableArchitecture: executableArchitecture,
            prefixArchitecture: architecture, runtimeID: runtime.id,
            runtimeName: runtime.displayName, runtimeVersion: runtime.wineVersion,
            legacyWrapper: gameProfile?.enforcedLegacyWrapper ?? profile.legacyWrapper,
            selected: selected, rankedCandidates: candidates, assessments: assessments,
            automaticFallbackAllowed: automatic
        )
    }

    static func executableDigest(_ executable: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: executable) else { return nil }
        defer { try? handle.close() }
        var hash = SHA256()
        do {
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                hash.update(data: chunk)
            }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        } catch { return nil }
    }
}
