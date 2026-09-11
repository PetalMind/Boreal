import Foundation
import CryptoKit

// MARK: - Evidence-backed compatibility models

nonisolated enum CompatibilityConfidence: String, Codable, CaseIterable, Hashable, Sendable {
    case low
    case medium
    case high
    case verified
}

nonisolated struct DetectionEvidence: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let source: String
    let value: String
    let detail: String

    init(id: UUID = UUID(), source: String, value: String, detail: String) {
        self.id = id
        self.source = source
        self.value = value
        self.detail = detail
    }
}

nonisolated struct DirectXDetectionResult: Codable, Hashable, Sendable {
    let api: GraphicsAPI?
    let confidence: CompatibilityConfidence
    let evidence: [DetectionEvidence]
    let candidates: [GraphicsAPI]

    init(
        api: GraphicsAPI?,
        confidence: CompatibilityConfidence,
        evidence: [DetectionEvidence],
        candidates: [GraphicsAPI] = []
    ) {
        self.api = api
        self.confidence = confidence
        self.evidence = evidence
        self.candidates = candidates
    }
}

nonisolated enum CompatibilityRecommendationSource: String, Codable, Hashable, Sendable {
    case executableImports
    case relatedGameFiles
    case gameProfile
    case storeMetadata
    case userProfile
    case runtimeCapabilities
    case fallback
}

nonisolated struct GraphicsStackRecommendation: Codable, Hashable, Sendable {
    let backend: GraphicsBackend
    let source: CompatibilityRecommendationSource
    let confidence: CompatibilityConfidence
    let reason: String
    let evidence: [DetectionEvidence]
}

nonisolated struct DependencyEvidence: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let source: String
    let library: String
    let detail: String

    init(id: UUID = UUID(), source: String, library: String, detail: String) {
        self.id = id
        self.source = source
        self.library = library
        self.detail = detail
    }
}

nonisolated struct DependencyRecommendation: Codable, Hashable, Sendable, Identifiable {
    let id: RuntimeDependency
    let dependency: RuntimeDependency
    let confidence: CompatibilityConfidence
    let reason: String
    let evidence: [DependencyEvidence]
    let isInstalled: Bool

    init(
        dependency: RuntimeDependency,
        confidence: CompatibilityConfidence,
        reason: String,
        evidence: [DependencyEvidence] = [],
        isInstalled: Bool = false
    ) {
        id = dependency
        self.dependency = dependency
        self.confidence = confidence
        self.reason = reason
        self.evidence = evidence
        self.isInstalled = isInstalled
    }
}

nonisolated struct RuntimeRecommendation: Codable, Hashable, Sendable {
    let runtimeID: String?
    let engine: RuntimeEngine?
    let confidence: CompatibilityConfidence
    let reason: String
    let evidence: [DetectionEvidence]
}

nonisolated struct CompatibilityWarning: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let detail: String
    let confidence: CompatibilityConfidence

    init(id: UUID = UUID(), title: String, detail: String, confidence: CompatibilityConfidence) {
        self.id = id
        self.title = title
        self.detail = detail
        self.confidence = confidence
    }
}

/// `ExecutableAnalysis` is the existing persisted-free PE discovery model.
/// Keep the vocabulary used by the compatibility feature without creating a
/// second executable inventory that could drift from the launch path.
typealias ExecutableCompatibilityAnalysis = ExecutableAnalysis

nonisolated struct CompatibilityResolutionRequest: Sendable {
    let applicationID: UUID
    let installation: GameInstallation?
    let executable: GameExecutable
    let executableAnalysis: ExecutableCompatibilityAnalysis?
    let storeReference: StoreReference?
    let gameProfile: GameGraphicsProfile?
    let userProfile: WineCompatibilityProfile
    let installedRuntimes: [InstalledRuntime]
    let executableURL: URL?
    let relatedFiles: [URL]
    let prefixURL: URL?

    init(
        applicationID: UUID,
        installation: GameInstallation? = nil,
        executable: GameExecutable,
        executableAnalysis: ExecutableCompatibilityAnalysis? = nil,
        storeReference: StoreReference? = nil,
        gameProfile: GameGraphicsProfile? = nil,
        userProfile: WineCompatibilityProfile = .default,
        installedRuntimes: [InstalledRuntime] = [],
        executableURL: URL? = nil,
        relatedFiles: [URL] = [],
        prefixURL: URL? = nil
    ) {
        self.applicationID = applicationID
        self.installation = installation
        self.executable = executable
        self.executableAnalysis = executableAnalysis
        self.storeReference = storeReference
        self.gameProfile = gameProfile
        self.userProfile = userProfile
        self.installedRuntimes = installedRuntimes
        self.executableURL = executableURL
        self.relatedFiles = relatedFiles
        self.prefixURL = prefixURL
    }
}

nonisolated struct CompatibilityResolution: Codable, Hashable, Sendable {
    let executableArchitecture: WindowsExecutableArchitecture
    let recommendedPrefixMode: WinePrefixMode
    let recommendedWindowsVersion: WineWindowsVersion
    let detectedDirectX: DirectXDetectionResult
    let recommendedGraphicsStack: GraphicsStackRecommendation
    let requiredDependencies: [DependencyRecommendation]
    let runtimeRecommendation: RuntimeRecommendation
    let warnings: [CompatibilityWarning]
    let confidence: CompatibilityConfidence
}

nonisolated enum DirectXDetector {
    static func detect(
        executable: URL?,
        relatedFiles: [URL] = [],
        profile: GameGraphicsProfile? = nil,
        fileManager: FileManager = .default
    ) -> DirectXDetectionResult {
        var evidence: [DetectionEvidence] = []
        var candidates = Set<GraphicsAPI>()

        if let executable {
            for signal in detectAPIs(in: executable, fileManager: fileManager) {
                let api = signal.api
                candidates.insert(api)
                evidence.append(DetectionEvidence(
                    source: signal.source,
                    value: api.displayName,
                    detail: "\(executable.lastPathComponent) contains a \(api.displayName) graphics signal (\(signal.library))."
                ))
            }
        }

        for file in relatedFiles {
            for signal in detectAPIs(in: file, fileManager: fileManager) where !candidates.contains(signal.api) {
                let api = signal.api
                candidates.insert(api)
                evidence.append(DetectionEvidence(
                    source: signal.source == "PE imports" ? "related PE imports" : "related game file",
                    value: api.displayName,
                    detail: "\(file.lastPathComponent) contains a \(api.displayName) graphics signal (\(signal.library))."
                ))
            }
        }

        if let profileAPI = profile?.enforcedAPI, profileAPI != .automatic {
            candidates.insert(profileAPI)
            evidence.append(DetectionEvidence(
                source: "known game profile",
                value: profileAPI.displayName,
                detail: "The local compatibility profile explicitly requires this DirectX API."
            ))
        } else if let profileAPI = profile?.defaultAPI, profileAPI != .automatic {
            candidates.insert(profileAPI)
            evidence.append(DetectionEvidence(
                source: "known game profile",
                value: profileAPI.displayName,
                detail: "The local compatibility profile lists this API as the default launch path."
            ))
        }

        let ordered = candidates.sorted { apiRank($0) < apiRank($1) }
        let selected: GraphicsAPI?
        let confidence: CompatibilityConfidence
        if ordered.count == 1 {
            selected = ordered.first
            confidence = evidence.contains(where: { $0.source == "PE imports" }) ? .high : .medium
        } else if ordered.isEmpty {
            selected = nil
            confidence = .low
        } else {
            // Conflicting strings/imports are deliberately not collapsed into a
            // confident answer. A game can ship optional render paths.
            selected = nil
            confidence = .low
        }
        return DirectXDetectionResult(
            api: selected,
            confidence: confidence,
            evidence: evidence,
            candidates: ordered
        )
    }

    private struct APISignal {
        let api: GraphicsAPI
        let library: String
        let source: String
    }

    private static func detectAPIs(in file: URL, fileManager: FileManager) -> [APISignal] {
        guard fileManager.fileExists(atPath: file.path) else { return [] }
        let inspection = WindowsPEInspection.inspect(file, fileManager: fileManager)
        if inspection.isPE {
            return inspection.imports.compactMap { library in
                api(for: library).map { APISignal(api: $0, library: library, source: "PE imports") }
            }
        }
        guard let data = readData(file, fileManager: fileManager) else { return [] }
        let text = String(decoding: data, as: UTF8.self).lowercased()
        return [
            ("d3d12.dll", GraphicsAPI.directX12),
            ("d3d12core.dll", GraphicsAPI.directX12),
            ("d3d11.dll", GraphicsAPI.directX11),
            ("dxgi.dll", GraphicsAPI.directX11),
            ("d3d10.dll", GraphicsAPI.directX10),
            ("d3d10_1.dll", GraphicsAPI.directX10),
            ("d3d10core.dll", GraphicsAPI.directX10),
            ("d3d9.dll", GraphicsAPI.directX9),
            ("d3dx9_", GraphicsAPI.directX9)
        ].compactMap { marker, api in
            text.contains(marker) ? APISignal(api: api, library: marker, source: "bounded file strings") : nil
        }
    }

    private static func api(for library: String) -> GraphicsAPI? {
        let name = library.lowercased()
        if name == "d3d12.dll" || name == "d3d12core.dll" { return .directX12 }
        if name == "d3d11.dll" || name == "dxgi.dll" { return .directX11 }
        if name == "d3d10.dll" || name == "d3d10_1.dll" || name == "d3d10core.dll" { return .directX10 }
        if name == "d3d9.dll" || name.hasPrefix("d3dx9_") { return .directX9 }
        return nil
    }

    private static func readData(_ url: URL, fileManager: FileManager) -> Data? {
        guard fileManager.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: 32 * 1_024 * 1_024)
    }

    private static func apiRank(_ api: GraphicsAPI) -> Int {
        switch api {
        case .directX12: 0
        case .directX11: 1
        case .directX10: 2
        case .directX9: 3
        case .automatic: 4
        }
    }
}

actor CompatibilityResolver {
    private let dependencyAnalyzer: DependencyAnalyzer

    init(dependencyAnalyzer: DependencyAnalyzer = DependencyAnalyzer()) {
        self.dependencyAnalyzer = dependencyAnalyzer
    }

    func resolve(_ request: CompatibilityResolutionRequest) async -> CompatibilityResolution {
        let architecture = resolveArchitecture(request)
        let directX = DirectXDetector.detect(
            executable: request.executableURL,
            relatedFiles: request.relatedFiles,
            profile: request.gameProfile
        )
        let api = directX.api ?? request.gameProfile?.defaultAPI ?? request.userProfile.graphicsAPI ?? .automatic
        let requiredEngine = request.storeReference.flatMap {
            GameRuntimeProfiles.requiredEngine(provider: $0.provider, externalID: $0.externalID)
        }
        let runtime = bestRuntime(for: request, api: api, architecture: architecture)
        let prefixMode = resolvePrefixMode(request: request, architecture: architecture, runtime: runtime)
        let prefixArchitecture: WinePrefixArchitecture = prefixMode == .legacyWin32 ? .win32 : .win64

        let graphicsResolution: GraphicsStackResolution
        if let runtime {
            graphicsResolution = GraphicsBackendResolver.resolve(
                api: api,
                requestedBackend: request.userProfile.graphicsBackend,
                gameProfile: request.gameProfile,
                runtime: runtime,
                architecture: prefixArchitecture,
                fallback: request.userProfile.graphicsFallback
            )
        } else {
            graphicsResolution = GraphicsStackResolution(
                stack: GraphicsStackCatalog.stack(for: .wineD3D)!,
                score: -1_000,
                reasons: ["No installed runtime is available for validation"]
            )
        }

        let dependencyRequirements = await dependencyAnalyzer.analyze(
            executable: request.executableURL,
            relatedFiles: request.relatedFiles,
            prefixURL: request.prefixURL,
            userDependencies: request.userProfile.requiredDependencies
        )
        let dependencies = dependencyRequirements.map { requirement in
            DependencyRecommendation(
                dependency: requirement.dependency,
                confidence: requirement.confidence,
                reason: requirement.reason,
                evidence: requirement.evidence,
                isInstalled: requirement.isInstalled
            )
        }

        var warnings: [CompatibilityWarning] = []
        if directX.api == nil {
            warnings.append(CompatibilityWarning(
                title: "DirectX API could not be confirmed",
                detail: directX.candidates.isEmpty
                    ? "No DirectX import was found in the supplied executable and related files."
                    : "The executable contains conflicting DirectX candidates: \(directX.candidates.map(\.displayName).joined(separator: ", ")).",
                confidence: directX.confidence
            ))
        }
        if request.executable.architecture == nil && architecture == .unknown {
            warnings.append(CompatibilityWarning(
                title: "Executable architecture is unknown",
                detail: "Prefix and runtime recommendations remain conservative until a valid PE header is available.",
                confidence: .low
            ))
        }
        if runtime == nil {
            warnings.append(CompatibilityWarning(
                title: "Runtime not installed",
                detail: "The recommendation is based on game evidence only and has not been validated against an installed runtime.",
                confidence: .low
            ))
        }
        if !graphicsResolution.isAvailable {
            warnings.append(CompatibilityWarning(
                title: "Graphics stack is unavailable",
                detail: graphicsResolution.reasons.joined(separator: "; "),
                confidence: .low
            ))
        }

        let graphicsSource: CompatibilityRecommendationSource = request.userProfile.graphicsBackend == .automatic
            ? (request.gameProfile == nil ? .runtimeCapabilities : .gameProfile)
            : .userProfile
        let graphicsConfidence: CompatibilityConfidence = request.userProfile.graphicsBackend == .automatic
            ? (request.gameProfile != nil && directX.api != nil ? .high : .medium)
            : .verified
        let graphicsRecommendation = GraphicsStackRecommendation(
            backend: graphicsResolution.stack.backend,
            source: graphicsSource,
            confidence: graphicsConfidence,
            reason: graphicsResolution.reasons.joined(separator: "; "),
            evidence: directX.evidence
        )
        let runtimeRecommendation = RuntimeRecommendation(
            runtimeID: runtime?.id,
            engine: runtime?.resolvedEngine ?? requiredEngine,
            confidence: runtime == nil ? .low : .high,
            reason: runtime.map { "Selected \($0.displayName) because it satisfies the executable and graphics constraints." }
                ?? "No installed runtime satisfies all constraints.",
            evidence: runtime.map {
                [DetectionEvidence(source: "runtime capabilities", value: $0.id, detail: $0.runtimeDescription)]
            } ?? []
        )

        return CompatibilityResolution(
            executableArchitecture: architecture,
            recommendedPrefixMode: prefixMode,
            recommendedWindowsVersion: request.userProfile.windowsVersion,
            detectedDirectX: directX,
            recommendedGraphicsStack: graphicsRecommendation,
            requiredDependencies: dependencies,
            runtimeRecommendation: runtimeRecommendation,
            warnings: warnings,
            confidence: overallConfidence(
                directX: directX,
                runtime: runtime,
                graphics: graphicsResolution,
                dependencies: dependencies
            )
        )
    }

    private func resolveArchitecture(_ request: CompatibilityResolutionRequest) -> WindowsExecutableArchitecture {
        if let architecture = request.executable.architecture {
            return architecture == .x86 ? .x86 : .x86_64
        }
        if let primary = request.executableAnalysis?.gameExecutable?.architecture {
            return primary
        }
        guard let url = request.executableURL else { return .unknown }
        return WindowsExecutableArchitecture.inspect(url)
    }

    private func bestRuntime(
        for request: CompatibilityResolutionRequest,
        api: GraphicsAPI,
        architecture: WindowsExecutableArchitecture
    ) -> InstalledRuntime? {
        let profile = request.userProfile
        let requiredEngine: RuntimeEngine?
        if let reference = request.storeReference {
            requiredEngine = GameRuntimeProfiles.requiredEngine(
                provider: reference.provider,
                externalID: reference.externalID
            )
        } else {
            requiredEngine = nil
        }
        let runtimeRequest = RuntimeSelectionRequest(
            architectures: [architecture],
            prefixMode: profile.prefixMode,
            requestedBackend: profile.graphicsBackend,
            directXAPI: api,
            gameProfile: request.gameProfile,
            requiredEngine: requiredEngine,
            runtimeIDOverride: profile.runtimeIDOverride
        )
        return request.installedRuntimes
            .filter { CompatibilityPreparationResolver.runtimeSatisfies($0, request: runtimeRequest) }
            .max { lhs, rhs in
                CompatibilityPreparationResolver.score(lhs, request: runtimeRequest)
                    < CompatibilityPreparationResolver.score(rhs, request: runtimeRequest)
            }
    }

    private func resolvePrefixMode(
        request: CompatibilityResolutionRequest,
        architecture: WindowsExecutableArchitecture,
        runtime: InstalledRuntime?
    ) -> WinePrefixMode {
        let supportsWoW64 = runtime?.features?.resolvedArchitectureCapabilities.usesNewWoW64 == true
        if let explicit = request.userProfile.prefixMode { return explicit }
        if supportsWoW64 { return .wow64 }
        return architecture == .x86 ? .legacyWin32 : .legacyWin64
    }

    private func overallConfidence(
        directX: DirectXDetectionResult,
        runtime: InstalledRuntime?,
        graphics: GraphicsStackResolution,
        dependencies: [DependencyRecommendation]
    ) -> CompatibilityConfidence {
        guard runtime != nil, graphics.isAvailable else { return .low }
        if directX.confidence == .low { return .medium }
        if dependencies.contains(where: { !$0.isInstalled && $0.confidence == .high }) { return .medium }
        return directX.confidence == .high ? .high : .medium
    }
}

// MARK: - Static dependency analysis

nonisolated struct DependencyRequirement: Codable, Hashable, Sendable, Identifiable {
    let id: RuntimeDependency
    let dependency: RuntimeDependency
    let confidence: CompatibilityConfidence
    let reason: String
    let evidence: [DependencyEvidence]
    let isInstalled: Bool
}

actor DependencyAnalyzer {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func analyze(
        executable: URL?,
        relatedFiles: [URL] = [],
        prefixURL: URL? = nil,
        userDependencies: Set<RuntimeDependency> = []
    ) -> [DependencyRequirement] {
        var evidenceByDependency: [RuntimeDependency: [DependencyEvidence]] = [:]
        let files = ([executable].compactMap { $0 } + relatedFiles).deduplicatedURLs
        for file in files {
            guard let data = read(file) else { continue }
            let inspection = WindowsPEInspection.inspect(file, fileManager: fileManager)
            let text = inspection.isPE ? nil : String(decoding: data, as: UTF8.self).lowercased()
            for (dependency, libraries, reason) in Self.signatures {
                for library in libraries where Self.matches(library, imports: inspection.imports, fallbackText: text) {
                    let source: String
                    if inspection.isPE {
                        source = file == executable ? "PE import table" : "related PE import table"
                    } else {
                        source = file == executable ? "bounded executable strings" : "related game file strings"
                    }
                    evidenceByDependency[dependency, default: []].append(DependencyEvidence(
                        source: source,
                        library: library,
                        detail: "\(file.lastPathComponent) references \(library), which maps to \(dependency.displayName)."
                    ))
                }
            }
        }

        var results: [DependencyRequirement] = []
        for dependency in RuntimeDependency.allCases {
            var evidence = evidenceByDependency[dependency] ?? []
            if userDependencies.contains(dependency) {
                evidence.append(DependencyEvidence(
                    source: "user profile",
                    library: dependency.rawValue,
                    detail: "This dependency was explicitly selected by the user."
                ))
            }
            guard !evidence.isEmpty else { continue }
            let installed = prefixURL.map { Self.isInstalled(dependency, prefixURL: $0, fileManager: fileManager) } ?? false
            let highConfidence = evidence.contains { $0.source == "PE import table" }
            results.append(DependencyRequirement(
                id: dependency,
                dependency: dependency,
                confidence: highConfidence ? .high : .medium,
                reason: highConfidence
                    ? "A Windows executable import requires \(dependency.displayName)."
                    : "A related game file indicates use of \(dependency.displayName).",
                evidence: evidence,
                isInstalled: installed
            ))
        }
        return results.sorted { $0.dependency.rawValue < $1.dependency.rawValue }
    }

    func analyzeLogs(
        _ logs: [URL],
        prefixURL: URL? = nil
    ) -> [DependencyRequirement] {
        let values = logs.compactMap(read).map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n").lowercased()
        var result: [DependencyRequirement] = []
        for (dependency, libraries, _) in Self.signatures {
            let missing = libraries.first { library in
                values.contains("not found") && values.contains(library.lowercased())
            }
            guard let missing else { continue }
            result.append(DependencyRequirement(
                id: dependency,
                dependency: dependency,
                confidence: .high,
                reason: "Wine logs report that \(missing) could not be loaded.",
                evidence: [DependencyEvidence(source: "Wine log", library: missing, detail: "The library was reported as missing by the runtime.")],
                isInstalled: prefixURL.map { Self.isInstalled(dependency, prefixURL: $0, fileManager: fileManager) } ?? false
            ))
        }
        return result.sorted { $0.dependency.rawValue < $1.dependency.rawValue }
    }

    private func read(_ url: URL) -> Data? {
        guard fileManager.fileExists(atPath: url.path), let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: 32 * 1_024 * 1_024)
    }

    private static let signatures: [(RuntimeDependency, [String], String)] = [
        (.vc2015To2022, ["vcruntime140.dll", "vcruntime140_1.dll", "msvcp140.dll"], "Visual C++ 2015–2022"),
        (.vc2010, ["msvcp100.dll", "msvcr100.dll"], "Visual C++ 2010"),
        (.xinput, ["xinput1_3.dll", "xinput1_4.dll", "xinput9_1_0.dll"], "XInput"),
        (.xact, ["xactengine3_7.dll", "xaudio2_7.dll", "x3daudio1_7.dll"], "XACT / legacy audio"),
        (.legacyDirectX, ["d3dx9_", "d3dcompiler_43.dll"], "Legacy DirectX"),
        (.physX, ["physxloader.dll", "physx3"], "PhysX"),
        (.dotNetFramework, ["mscoree.dll"], ".NET Framework")
    ]

    private static func matches(_ signature: String, imports: Set<String>, fallbackText: String?) -> Bool {
        let normalized = signature.lowercased()
        if imports.contains(where: { imported in
            imported == normalized || (normalized.hasSuffix("_") && imported.hasPrefix(normalized)) || (normalized.hasSuffix("3") && imported.hasPrefix(normalized))
        }) {
            return true
        }
        return fallbackText?.contains(normalized) == true
    }

    private static func isInstalled(_ dependency: RuntimeDependency, prefixURL: URL, fileManager: FileManager) -> Bool {
        let roots = [
            prefixURL.appending(path: "drive_c/windows/system32", directoryHint: .isDirectory),
            prefixURL.appending(path: "drive_c/windows/syswow64", directoryHint: .isDirectory)
        ]
        return roots.contains { root in
            guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return false }
            for case let url as URL in enumerator {
                let name = url.lastPathComponent.lowercased()
                if dependency.detectionLibraries.contains(where: { name == $0.lowercased() || ($0.hasSuffix("_") && name.hasPrefix($0.lowercased())) }) {
                    return true
                }
            }
            return false
        }
    }
}

// MARK: - Launch diagnostics

nonisolated enum LaunchFailureCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case missingDependency
    case architectureMismatch
    case unsupportedDirectX
    case graphicsInitialization
    case runtimeFailure
    case missingExecutable
    case invalidWorkingDirectory
    case providerFailure
    case launcherFailure
    case antiCheatSuspected
    case permissionFailure
    case corruptedPrefix
    case unknown
}

nonisolated struct DiagnosticEvidence: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let source: String
    let detail: String

    init(id: UUID = UUID(), source: String, detail: String) {
        self.id = id
        self.source = source
        self.detail = detail
    }
}

nonisolated enum DiagnosticActionKind: String, Codable, Hashable, Sendable {
    case installDependency
    case changeGraphicsBackend
    case inspectLogs
    case verifyInstallation
    case rebuildEnvironment
    case revealExecutable
    case retry
}

nonisolated extension DiagnosticActionKind {
    var symbol: String {
        switch self {
        case .installDependency: "shippingbox"
        case .changeGraphicsBackend: "paintbrush.pointed"
        case .inspectLogs: "doc.text.magnifyingglass"
        case .verifyInstallation: "checkmark.seal"
        case .rebuildEnvironment: "arrow.triangle.2.circlepath"
        case .revealExecutable: "folder"
        case .retry: "arrow.clockwise"
        }
    }
}

nonisolated struct DiagnosticAction: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let kind: DiagnosticActionKind
    let title: String
    let requiresConfirmation: Bool

    init(id: UUID = UUID(), kind: DiagnosticActionKind, title: String, requiresConfirmation: Bool = false) {
        self.id = id
        self.kind = kind
        self.title = title
        self.requiresConfirmation = requiresConfirmation
    }
}

nonisolated struct LaunchFailureInput: Sendable {
    let exitCode: Int32?
    let stdout: String
    let stderr: String
    let wineLogs: [String]
    let rendererLogs: [String]
    let launchPlan: LaunchPlan?
    let runtime: InstalledRuntime?
    let environment: ManagedBorealEnvironment?
    let dependencyStatuses: [RuntimeDependencyStatus]

    init(
        exitCode: Int32? = nil,
        stdout: String = "",
        stderr: String = "",
        wineLogs: [String] = [],
        rendererLogs: [String] = [],
        launchPlan: LaunchPlan? = nil,
        runtime: InstalledRuntime? = nil,
        environment: ManagedBorealEnvironment? = nil,
        dependencyStatuses: [RuntimeDependencyStatus] = []
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.wineLogs = wineLogs
        self.rendererLogs = rendererLogs
        self.launchPlan = launchPlan
        self.runtime = runtime
        self.environment = environment
        self.dependencyStatuses = dependencyStatuses
    }
}

nonisolated struct LaunchFailureDiagnosis: Codable, Hashable, Sendable {
    let category: LaunchFailureCategory
    let confidence: CompatibilityConfidence
    let summary: String
    let evidence: [DiagnosticEvidence]
    let suggestedActions: [DiagnosticAction]
}

nonisolated enum LaunchRepairError: LocalizedError, Sendable {
    case unsupported(LaunchFailureCategory)
    case noActionableDependency

    var errorDescription: String? {
        switch self {
        case .unsupported(let category): "No confirmed automatic repair is available for \(category.rawValue)."
        case .noActionableDependency: "The failure did not identify a missing dependency that can be installed safely."
        }
    }
}

actor LaunchFailureAnalyzer {
    func analyze(_ input: LaunchFailureInput) -> LaunchFailureDiagnosis {
        let output = ([input.stdout, input.stderr] + input.wineLogs + input.rendererLogs).joined(separator: "\n")
        let lower = output.lowercased()
        if let plan = input.launchPlan {
            if !FileManager.default.fileExists(atPath: plan.executable.path) {
                return diagnosis(.missingExecutable, .verified, "The game executable is missing.", [
                    DiagnosticEvidence(source: "Launch plan", detail: plan.executable.path)
                ], [.init(kind: .revealExecutable, title: "Reveal installation")])
            }
            if !FileManager.default.fileExists(atPath: plan.workingDirectory.path) {
                return diagnosis(.invalidWorkingDirectory, .verified, "The launch working directory is missing.", [
                    DiagnosticEvidence(source: "Launch plan", detail: plan.workingDirectory.path)
                ], [.init(kind: .verifyInstallation, title: "Verify installation")])
            }
            if plan.executableArchitecture == .x86 && plan.prefixMode == .legacyWin64 {
                return diagnosis(.architectureMismatch, .high, "The 32-bit executable is paired with a legacy Win64 prefix.", [
                    DiagnosticEvidence(source: "Launch plan", detail: "Executable architecture: x86; prefix: legacy Win64")
                ], [.init(kind: .rebuildEnvironment, title: "Rebuild with a compatible prefix", requiresConfirmation: true)])
            }
            if plan.executableArchitecture == .x86_64 && plan.prefixMode == .legacyWin32 {
                return diagnosis(.architectureMismatch, .high, "The 64-bit executable cannot run in a legacy Win32 prefix.", [
                    DiagnosticEvidence(source: "Launch plan", detail: "Executable architecture: x86_64; prefix: legacy Win32")
                ], [.init(kind: .rebuildEnvironment, title: "Rebuild with a compatible prefix", requiresConfirmation: true)])
            }
        }

        if let missing = missingDependency(in: lower, statuses: input.dependencyStatuses) {
            return diagnosis(.missingDependency, .high, "A Windows dependency could not be loaded.", [
                DiagnosticEvidence(source: "Wine output", detail: missing)
            ], [.init(kind: .installDependency, title: "Install missing dependency", requiresConfirmation: true), .init(kind: .inspectLogs, title: "View logs")])
        }
        if lower.contains("anti-cheat") || lower.contains("easyanticheat") || lower.contains("battleye") || lower.contains("eac") {
            return diagnosis(.antiCheatSuspected, .medium, "The launch output suggests an anti-cheat compatibility restriction.", [
                DiagnosticEvidence(source: "Launch output", detail: "An anti-cheat marker was found; the game vendor may block Wine.")
            ], [.init(kind: .inspectLogs, title: "View logs")])
        }
        if lower.contains("d3d12") && (input.launchPlan?.graphicsBackend == .dxmt || input.launchPlan?.graphicsBackend == .dxvk) {
            return diagnosis(.unsupportedDirectX, .high, "DirectX 12 initialization is not supported by the selected renderer.", [
                DiagnosticEvidence(source: "Renderer output", detail: "DirectX 12 was requested with \(input.launchPlan?.graphicsBackend.displayName ?? "the current renderer").")
            ], [.init(kind: .changeGraphicsBackend, title: "Choose a DirectX 12 renderer"), .init(kind: .inspectLogs, title: "View logs")])
        }
        if lower.contains("err:") && (lower.contains("d3d") || lower.contains("dxgi") || lower.contains("vulkan") || lower.contains("metal")) {
            return diagnosis(.graphicsInitialization, .medium, "The graphics renderer failed during initialization.", [
                DiagnosticEvidence(source: "Renderer output", detail: firstRelevantLine(in: output, terms: ["d3d", "dxgi", "vulkan", "metal"]))
            ], [.init(kind: .changeGraphicsBackend, title: "Review graphics settings"), .init(kind: .inspectLogs, title: "View logs")])
        }
        if lower.contains("wineserver") || lower.contains("wineboot") || lower.contains("prefix") && lower.contains("corrupt") {
            return diagnosis(.corruptedPrefix, .medium, "The Wine environment appears to be incomplete or corrupted.", [
                DiagnosticEvidence(source: "Wine output", detail: firstRelevantLine(in: output, terms: ["wineserver", "wineboot", "prefix", "corrupt"]))
            ], [.init(kind: .rebuildEnvironment, title: "Rebuild environment", requiresConfirmation: true), .init(kind: .inspectLogs, title: "View logs")])
        }
        if lower.contains("permission denied") || lower.contains("operation not permitted") {
            return diagnosis(.permissionFailure, .high, "The game or environment could not be accessed.", [
                DiagnosticEvidence(source: "Launch output", detail: firstRelevantLine(in: output, terms: ["permission denied", "operation not permitted"]))
            ], [.init(kind: .verifyInstallation, title: "Verify installation"), .init(kind: .inspectLogs, title: "View logs")])
        }
        if (lower.contains("steam") || lower.contains("gog") || lower.contains("legendary") || lower.contains("epic") || lower.contains("provider")) &&
            (lower.contains("authentication") || lower.contains("login") || lower.contains("request failed") || lower.contains("api error") || lower.contains("download failed")) {
            return diagnosis(.providerFailure, .medium, "The store provider failed before the game could launch.", [
                DiagnosticEvidence(source: "Provider output", detail: firstRelevantLine(in: output, terms: ["authentication", "login", "request failed", "api error", "download failed"]))
            ], [.init(kind: .verifyInstallation, title: "Check provider connection"), .init(kind: .inspectLogs, title: "View logs")])
        }
        if lower.contains("launcher") && (lower.contains("failed") || lower.contains("not found")) {
            return diagnosis(.launcherFailure, .medium, "The game's launcher failed before the game executable started.", [
                DiagnosticEvidence(source: "Launch output", detail: firstRelevantLine(in: output, terms: ["launcher", "failed", "not found"]))
            ], [.init(kind: .verifyInstallation, title: "Verify installation"), .init(kind: .inspectLogs, title: "View logs")])
        }
        if let exitCode = input.exitCode, exitCode != 0 {
            return diagnosis(.runtimeFailure, .low, "The Windows process exited with code \(exitCode).", [
                DiagnosticEvidence(source: "Process result", detail: "Exit code: \(exitCode)")
            ], [.init(kind: .inspectLogs, title: "View logs"), .init(kind: .retry, title: "Try again")])
        }
        return diagnosis(.unknown, .low, "Boreal could not determine the launch failure cause.", [
            DiagnosticEvidence(source: "Launch output", detail: "No recognized high-signal failure marker was found.")
        ], [.init(kind: .inspectLogs, title: "View logs"), .init(kind: .retry, title: "Try again")])
    }

    private func missingDependency(in output: String, statuses: [RuntimeDependencyStatus]) -> String? {
        for dependency in RuntimeDependency.allCases {
            let names = dependency.detectionLibraries.map { $0.lowercased() }
            if let name = names.first(where: { output.contains($0) }), output.contains("not found") || output.contains("failed to load") || output.contains("could not load") {
                return "\(name) was reported as missing (\(dependency.displayName))."
            }
            if let status = statuses.first(where: { $0.dependency == dependency }), status.state == .missing, output.contains("load") {
                return "\(dependency.displayName) is marked missing and the launch output reports a load failure."
            }
        }
        return nil
    }

    private func diagnosis(
        _ category: LaunchFailureCategory,
        _ confidence: CompatibilityConfidence,
        _ summary: String,
        _ evidence: [DiagnosticEvidence],
        _ actions: [DiagnosticAction]
    ) -> LaunchFailureDiagnosis {
        LaunchFailureDiagnosis(category: category, confidence: confidence, summary: summary, evidence: evidence, suggestedActions: actions)
    }

    private func firstRelevantLine(in output: String, terms: [String]) -> String {
        output.split(separator: "\n").first { line in
            let lower = line.lowercased()
            return terms.contains { lower.contains($0) }
        }.map(String.init) ?? "Relevant diagnostic output was found."
    }
}

// MARK: - Trace IDs and operation state

nonisolated struct OperationTraceID: Hashable, Codable, Sendable, CustomStringConvertible {
    let rawValue: UUID

    init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
    var description: String { rawValue.uuidString.lowercased() }
    var shortValue: String { String(description.prefix(8)) }
}

nonisolated enum BorealOperationKind: String, Codable, Hashable, Sendable {
    case creatingSnapshot
    case restoringSnapshot
    case analyzingCompatibility
    case scanningSaves
    case creatingSaveBackup
    case calculatingStorage
    case repairingEnvironment
    case benchmarkCapture
    case installingModification
}

nonisolated struct BorealOperationState: Codable, Hashable, Sendable, Identifiable {
    let id: OperationTraceID
    let kind: BorealOperationKind
    var progress: Double?
    var phase: String
    var canCancel: Bool

    init(id: OperationTraceID = OperationTraceID(), kind: BorealOperationKind, progress: Double? = nil, phase: String, canCancel: Bool = true) {
        self.id = id
        self.kind = kind
        self.progress = progress
        self.phase = phase
        self.canCancel = canCancel
    }
}

// MARK: - Environment snapshots and rollback

nonisolated enum SnapshotReason: String, Codable, CaseIterable, Hashable, Sendable {
    case dependencyInstallation
    case graphicsBackendChange
    case dllOverrideChange
    case windowsVersionChange
    case manualCompatibilityChange
    case environmentRepair
    case runtimeMigration
    case modInstallation
    case beforeRestore
}

nonisolated enum SnapshotStorageMode: String, Codable, Hashable, Sendable {
    case cloneOnWrite
    case copy
}

nonisolated struct EnvironmentSnapshot: Codable, Identifiable, Hashable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let environmentID: UUID
    let createdAt: Date
    let reason: SnapshotReason
    let sourceConfiguration: EnvironmentConfiguration
    let snapshotURL: URL
    let sizeBytes: Int64?
    let storageMode: SnapshotStorageMode
    let traceID: OperationTraceID

    init(
        schemaVersion: Int = BorealStorageSchema.current,
        id: UUID = UUID(),
        environmentID: UUID,
        createdAt: Date = .now,
        reason: SnapshotReason,
        sourceConfiguration: EnvironmentConfiguration,
        snapshotURL: URL,
        sizeBytes: Int64? = nil,
        storageMode: SnapshotStorageMode = .copy,
        traceID: OperationTraceID = OperationTraceID()
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.environmentID = environmentID
        self.createdAt = createdAt
        self.reason = reason
        self.sourceConfiguration = sourceConfiguration
        self.snapshotURL = snapshotURL
        self.sizeBytes = sizeBytes
        self.storageMode = storageMode
        self.traceID = traceID
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, environmentID, createdAt, reason, sourceConfiguration
        case snapshotURL, sizeBytes, storageMode, traceID
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard schemaVersion <= BorealStorageSchema.current else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: values, debugDescription: "Unsupported snapshot schema version")
        }
        id = try values.decode(UUID.self, forKey: .id)
        environmentID = try values.decode(UUID.self, forKey: .environmentID)
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        reason = try values.decodeIfPresent(SnapshotReason.self, forKey: .reason) ?? .manualCompatibilityChange
        sourceConfiguration = try values.decode(EnvironmentConfiguration.self, forKey: .sourceConfiguration)
        snapshotURL = try values.decode(URL.self, forKey: .snapshotURL)
        sizeBytes = try values.decodeIfPresent(Int64.self, forKey: .sizeBytes)
        storageMode = try values.decodeIfPresent(SnapshotStorageMode.self, forKey: .storageMode) ?? .copy
        traceID = try values.decodeIfPresent(OperationTraceID.self, forKey: .traceID) ?? OperationTraceID()
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(environmentID, forKey: .environmentID)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(reason, forKey: .reason)
        try values.encode(sourceConfiguration, forKey: .sourceConfiguration)
        try values.encode(snapshotURL, forKey: .snapshotURL)
        try values.encodeIfPresent(sizeBytes, forKey: .sizeBytes)
        try values.encode(storageMode, forKey: .storageMode)
        try values.encode(traceID, forKey: .traceID)
    }
}

nonisolated enum SnapshotError: LocalizedError, Sendable {
    case activeSession
    case insufficientSpace
    case sourceMissing
    case validationFailed
    case restoreFailed
    case invalidSnapshot

    var errorDescription: String? {
        switch self {
        case .activeSession: "The environment has an active game session. Stop it before restoring a snapshot."
        case .insufficientSpace: "There is not enough space to create a safe snapshot."
        case .sourceMissing: "The environment files to snapshot are missing."
        case .validationFailed: "The snapshot did not pass validation."
        case .restoreFailed: "The environment could not be restored atomically."
        case .invalidSnapshot: "The snapshot is incomplete or belongs to another environment."
        }
    }
}

actor EnvironmentSnapshotManager {
    private let snapshotsRootURL: URL
    private let fileManager: FileManager

    init(snapshotsRootURL: URL, fileManager: FileManager = .default) {
        self.snapshotsRootURL = snapshotsRootURL.standardizedFileURL
        self.fileManager = fileManager
    }

    init(applicationSupportURL: URL, fileManager: FileManager = .default) {
        self.init(snapshotsRootURL: applicationSupportURL.appending(path: "Snapshots", directoryHint: .isDirectory), fileManager: fileManager)
    }

    func createSnapshot(
        for environment: ManagedBorealEnvironment,
        reason: SnapshotReason,
        traceID: OperationTraceID = OperationTraceID()
    ) async throws -> EnvironmentSnapshot {
        guard fileManager.fileExists(atPath: environment.rootURL.path) else { throw SnapshotError.sourceMissing }
        let sourceSize = allocatedSize(of: environment.rootURL)
        let volumeValues = try? snapshotsRootURL.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let sourceSize,
           let volumeValues,
           let available = volumeValues.volumeAvailableCapacityForImportantUsage,
           available < sourceSize {
            throw SnapshotError.insufficientSpace
        }
        let snapshotID = UUID()
        let directory = snapshotsRootURL
            .appending(path: environment.id.uuidString, directoryHint: .isDirectory)
            .appending(path: snapshotID.uuidString, directoryHint: .isDirectory)
        let staging = directory.deletingLastPathComponent().appending(path: ".\(snapshotID.uuidString).staging", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.removeItem(at: staging)
        do {
            try fileManager.copyItem(at: environment.rootURL, to: staging)
            let snapshot = EnvironmentSnapshot(
                id: snapshotID,
                environmentID: environment.id,
                reason: reason,
                sourceConfiguration: environment.configuration,
                snapshotURL: directory,
                sizeBytes: allocatedSize(of: staging),
                storageMode: .copy,
                traceID: traceID
            )
            guard validateSnapshot(staging, environmentID: environment.id) else { throw SnapshotError.validationFailed }
            try fileManager.moveItem(at: staging, to: directory)
            try writeMetadata(snapshot)
            return snapshot
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    func snapshots(for environmentID: UUID) -> [EnvironmentSnapshot] {
        let directory = snapshotsRootURL.appending(path: environmentID.uuidString, directoryHint: .isDirectory)
        guard let children = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        return children.compactMap { child in
            let metadataURL = child.appending(path: "snapshot.json")
            guard let data = try? Data(contentsOf: metadataURL), let value = try? JSONDecoder().decode(EnvironmentSnapshot.self, from: data), fileManager.fileExists(atPath: value.snapshotURL.path) else { return nil }
            return value
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func restore(
        _ snapshot: EnvironmentSnapshot,
        to environment: ManagedBorealEnvironment,
        activeSession: Bool,
        preserveCurrent: Bool = true,
        traceID: OperationTraceID = OperationTraceID()
    ) async throws -> ManagedBorealEnvironment {
        guard !activeSession else { throw SnapshotError.activeSession }
        guard snapshot.environmentID == environment.id,
              snapshot.snapshotURL.standardizedFileURL.path.hasPrefix(snapshotsRootURL.path + "/"),
              fileManager.fileExists(atPath: snapshot.snapshotURL.path),
              validateSnapshot(snapshot.snapshotURL, environmentID: environment.id) else { throw SnapshotError.invalidSnapshot }

        if preserveCurrent {
            _ = try await createSnapshot(for: environment, reason: .beforeRestore, traceID: traceID)
        }
        let parent = environment.rootURL.deletingLastPathComponent()
        let staging = parent.appending(path: ".\(environment.id.uuidString).restore-staging", directoryHint: .isDirectory)
        let displaced = parent.appending(path: ".\(environment.id.uuidString).restore-previous", directoryHint: .isDirectory)
        try? fileManager.removeItem(at: staging)
        try? fileManager.removeItem(at: displaced)
        do {
            try fileManager.copyItem(at: snapshot.snapshotURL, to: staging)
            guard validateSnapshot(staging, environmentID: environment.id) else { throw SnapshotError.validationFailed }
            if fileManager.fileExists(atPath: environment.rootURL.path) { try fileManager.moveItem(at: environment.rootURL, to: displaced) }
            try fileManager.moveItem(at: staging, to: environment.rootURL)
            var restored = environment
            restored.configuration = snapshot.sourceConfiguration
            restored.state = .ready
            try writeEnvironment(restored)
            try? fileManager.removeItem(at: displaced)
            return restored
        } catch {
            try? fileManager.removeItem(at: staging)
            if fileManager.fileExists(atPath: displaced.path) {
                try? fileManager.removeItem(at: environment.rootURL)
                try? fileManager.moveItem(at: displaced, to: environment.rootURL)
            }
            throw error is SnapshotError ? error : SnapshotError.restoreFailed
        }
    }

    func delete(_ snapshot: EnvironmentSnapshot) throws {
        guard snapshot.snapshotURL.standardizedFileURL.path.hasPrefix(snapshotsRootURL.path + "/") else { throw SnapshotError.invalidSnapshot }
        try fileManager.removeItem(at: snapshot.snapshotURL)
    }

    private func writeMetadata(_ snapshot: EnvironmentSnapshot) throws {
        let metadataURL = snapshot.snapshotURL.appending(path: "snapshot.json")
        try fileManager.createDirectory(at: snapshot.snapshotURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: metadataURL, options: .atomic)
    }

    private func writeEnvironment(_ environment: ManagedBorealEnvironment) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(environment).write(to: environment.rootURL.appending(path: "environment.json"), options: .atomic)
    }

    private func validateSnapshot(_ url: URL, environmentID: UUID) -> Bool {
        guard fileManager.fileExists(atPath: url.appending(path: "environment.json").path),
              let data = try? Data(contentsOf: url.appending(path: "environment.json")),
              let value = try? JSONDecoder().decode(ManagedBorealEnvironment.self, from: data),
              value.id == environmentID else { return false }
        return true
    }

    private func allocatedSize(of url: URL) -> Int64? {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return nil }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            guard let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .fileSizeKey]), values.isRegularFile == true else { continue }
            total += Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total > 0 ? total : nil
    }
}

// MARK: - Saves

nonisolated enum SaveLocationSource: String, Codable, Hashable, Sendable {
    case compatibilityProfile
    case steamMetadata
    case knownPath
    case heuristic
    case manual
}

nonisolated struct GameSaveLocation: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let relativePath: String
    let source: SaveLocationSource
    let confidence: CompatibilityConfidence

    init(id: UUID = UUID(), relativePath: String, source: SaveLocationSource, confidence: CompatibilityConfidence) {
        self.id = id
        self.relativePath = relativePath
        self.source = source
        self.confidence = confidence
    }
}

nonisolated enum SaveBackupTrigger: String, Codable, Hashable, Sendable {
    case manual
    case beforeEnvironmentRebuild
    case beforeUninstall
    case beforeSnapshotRestore
    case afterGameExit
}

nonisolated struct SaveBackupRetentionPolicy: Codable, Hashable, Sendable {
    var keepLast: Int = 10
    var keepDailyDays: Int = 7
    var keepWeeklyWeeks: Int = 4

    static let `default` = SaveBackupRetentionPolicy()
}

nonisolated struct GameSaveBackup: Codable, Identifiable, Hashable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let applicationID: UUID
    let createdAt: Date
    let sourcePaths: [String]
    let archiveURL: URL
    let sizeBytes: Int64
    let trigger: SaveBackupTrigger
    let traceID: OperationTraceID

    init(
        schemaVersion: Int = BorealStorageSchema.current,
        id: UUID,
        applicationID: UUID,
        createdAt: Date,
        sourcePaths: [String],
        archiveURL: URL,
        sizeBytes: Int64,
        trigger: SaveBackupTrigger,
        traceID: OperationTraceID
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.applicationID = applicationID
        self.createdAt = createdAt
        self.sourcePaths = sourcePaths
        self.archiveURL = archiveURL
        self.sizeBytes = sizeBytes
        self.trigger = trigger
        self.traceID = traceID
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, applicationID, createdAt, sourcePaths, archiveURL, sizeBytes, trigger, traceID
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard schemaVersion <= BorealStorageSchema.current else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: values, debugDescription: "Unsupported save backup schema version")
        }
        id = try values.decode(UUID.self, forKey: .id)
        applicationID = try values.decode(UUID.self, forKey: .applicationID)
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        sourcePaths = try values.decodeIfPresent([String].self, forKey: .sourcePaths) ?? []
        archiveURL = try values.decode(URL.self, forKey: .archiveURL)
        sizeBytes = try values.decodeIfPresent(Int64.self, forKey: .sizeBytes) ?? 0
        trigger = try values.decodeIfPresent(SaveBackupTrigger.self, forKey: .trigger) ?? .manual
        traceID = try values.decodeIfPresent(OperationTraceID.self, forKey: .traceID) ?? OperationTraceID()
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(applicationID, forKey: .applicationID)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(sourcePaths, forKey: .sourcePaths)
        try values.encode(archiveURL, forKey: .archiveURL)
        try values.encode(sizeBytes, forKey: .sizeBytes)
        try values.encode(trigger, forKey: .trigger)
        try values.encode(traceID, forKey: .traceID)
    }
}

nonisolated enum SaveManagerError: LocalizedError, Sendable {
    case noSaveData
    case invalidBackup
    case restoreFailed

    var errorDescription: String? {
        switch self {
        case .noSaveData: "No existing save data was found at the selected locations."
        case .invalidBackup: "The save backup is incomplete or outside Boreal's backup directory."
        case .restoreFailed: "The save backup could not be restored safely."
        }
    }
}

actor GameSaveManager {
    private let supportURL: URL
    private let fileManager: FileManager

    init(applicationSupportURL: URL, fileManager: FileManager = .default) {
        supportURL = applicationSupportURL.standardizedFileURL
        self.fileManager = fileManager
    }

    func detect(
        applicationID: UUID,
        installationURL: URL,
        prefixURL: URL? = nil,
        knownRelativePaths: [String] = [],
        manualRelativePaths: [String] = []
    ) -> [GameSaveLocation] {
        var candidates: [GameSaveLocation] = []
        candidates += knownRelativePaths.compactMap { path in
            let value = normalized(path)
            return isSafeRelativePath(value) ? GameSaveLocation(relativePath: value, source: .compatibilityProfile, confidence: .high) : nil
        }
        candidates += manualRelativePaths.compactMap { path in
            let value = normalized(path)
            return isSafeRelativePath(value) ? GameSaveLocation(relativePath: value, source: .manual, confidence: .verified) : nil
        }
        if let prefixURL {
            let users = prefixURL.appending(path: "drive_c/users", directoryHint: .isDirectory)
            if let userDirectories = try? fileManager.contentsOfDirectory(at: users, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                for user in userDirectories where isDirectory(user) {
                    for path in ["Documents", "Documents/My Games", "Saved Games", "AppData/Local", "AppData/LocalLow", "AppData/Roaming"] {
                        let candidate = user.appending(path: path, directoryHint: .isDirectory)
                        if isDirectory(candidate) {
                            candidates.append(GameSaveLocation(relativePath: relativePath(candidate, from: prefixURL), source: .knownPath, confidence: .medium))
                        }
                    }
                }
            }
        }
        for path in ["userdata", "steamapps/compatdata"] {
            let candidate = installationURL.appending(path: path, directoryHint: .isDirectory)
            if isDirectory(candidate) {
                candidates.append(GameSaveLocation(relativePath: relativePath(candidate, from: installationURL), source: .steamMetadata, confidence: .medium))
            }
        }
        return deduplicate(candidates)
    }

    func backup(
        applicationID: UUID,
        locations: [URL],
        trigger: SaveBackupTrigger,
        traceID: OperationTraceID = OperationTraceID()
    ) throws -> GameSaveBackup {
        let existing = locations.filter { fileManager.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { throw SaveManagerError.noSaveData }
        let id = UUID()
        let parent = supportURL.appending(path: "SaveBackups/\(applicationID.uuidString)", directoryHint: .isDirectory)
        let archiveURL = parent.appending(path: id.uuidString, directoryHint: .isDirectory)
        let staging = parent.appending(path: ".\(id.uuidString).staging", directoryHint: .isDirectory)
        let sourcesURL = staging.appending(path: "Sources", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: staging)
        do {
            try fileManager.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
            for (index, source) in existing.enumerated() {
                try fileManager.copyItem(at: source, to: sourcesURL.appending(path: "\(index)-\(source.lastPathComponent)"))
            }
            let paths = existing.map(\.path)
            let size = allocatedSize(of: staging)
            let backup = GameSaveBackup(id: id, applicationID: applicationID, createdAt: .now, sourcePaths: paths, archiveURL: archiveURL, sizeBytes: size, trigger: trigger, traceID: traceID)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(backup).write(to: staging.appending(path: "backup.json"), options: .atomic)
            try fileManager.moveItem(at: staging, to: archiveURL)
            return backup
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    func restore(_ backup: GameSaveBackup, allowedRoots: [URL] = []) throws {
        let root = supportURL.appending(path: "SaveBackups").standardizedFileURL
        guard backup.archiveURL.standardizedFileURL.path.hasPrefix(root.path + "/"),
              fileManager.fileExists(atPath: backup.archiveURL.appending(path: "Sources").path) else { throw SaveManagerError.invalidBackup }
        guard backup.sourcePaths.count > 0 else { throw SaveManagerError.invalidBackup }
        let sources = try fileManager.contentsOfDirectory(at: backup.archiveURL.appending(path: "Sources"), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]).sorted { sourceIndex($0) < sourceIndex($1) }
        guard sources.count == backup.sourcePaths.count else { throw SaveManagerError.invalidBackup }
        var staged: [URL] = []
        var displaced: [(destination: URL, previous: URL)] = []
        do {
            for (source, destinationPath) in zip(sources, backup.sourcePaths) {
                let destination = URL(fileURLWithPath: destinationPath)
                guard !destinationPath.isEmpty,
                      destination.isFileURL,
                      allowedRoots.isEmpty || allowedRoots.contains(where: { isWithin(destination, root: $0) }) else {
                    throw SaveManagerError.invalidBackup
                }
                let suffix = UUID().uuidString
                let staging = destination.deletingLastPathComponent().appending(path: ".\(destination.lastPathComponent).boreal-restore-\(suffix)")
                let previous = destination.deletingLastPathComponent().appending(path: ".\(destination.lastPathComponent).boreal-previous-\(suffix)")
                try fileManager.copyItem(at: source, to: staging)
                staged.append(staging)
                displaced.append((destination, previous))
                if fileManager.fileExists(atPath: destination.path) { try fileManager.moveItem(at: destination, to: previous) }
                try fileManager.moveItem(at: staging, to: destination)
            }
            for previous in displaced { try? fileManager.removeItem(at: previous.previous) }
            staged.removeAll()
        } catch {
            for staging in staged { try? fileManager.removeItem(at: staging) }
            for pair in displaced.reversed() {
                if fileManager.fileExists(atPath: pair.previous.path) {
                    try? fileManager.removeItem(at: pair.destination)
                    try? fileManager.moveItem(at: pair.previous, to: pair.destination)
                }
            }
            throw error is SaveManagerError ? error : SaveManagerError.restoreFailed
        }
    }

    func backups(for applicationID: UUID) -> [GameSaveBackup] {
        let root = supportURL.appending(path: "SaveBackups/\(applicationID.uuidString)", directoryHint: .isDirectory)
        guard let folders = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appending(path: "backup.json")) else { return nil }
            return try? JSONDecoder().decode(GameSaveBackup.self, from: data)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func prune(
        applicationID: UUID,
        policy: SaveBackupRetentionPolicy = .default,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> [UUID] {
        let all = backups(for: applicationID)
        var keep = Set(all.prefix(max(0, policy.keepLast)).map(\.id))
        let dailyCutoff = calendar.date(byAdding: .day, value: -policy.keepDailyDays, to: now) ?? now
        let weeklyCutoff = calendar.date(byAdding: .weekOfYear, value: -policy.keepWeeklyWeeks, to: now) ?? now
        for backup in all where backup.createdAt >= dailyCutoff { keep.insert(backup.id) }
        for backup in all where backup.createdAt >= weeklyCutoff {
            let week = calendar.component(.weekOfYear, from: backup.createdAt)
            if !all.contains(where: { $0.id != backup.id && $0.createdAt > backup.createdAt && calendar.component(.weekOfYear, from: $0.createdAt) == week }) {
                keep.insert(backup.id)
            }
        }
        var removed: [UUID] = []
        for backup in all where !keep.contains(backup.id) {
            try fileManager.removeItem(at: backup.archiveURL)
            removed.append(backup.id)
        }
        return removed
    }

    private func normalized(_ path: String) -> String { path.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
    private func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.split(separator: "/").contains("..")
    }
    private func isDirectory(_ url: URL) -> Bool { (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    private func relativePath(_ url: URL, from root: URL) -> String { String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
    private func isWithin(_ url: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = url.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }
    private func sourceIndex(_ url: URL) -> Int {
        Int(url.lastPathComponent.split(separator: "-", maxSplits: 1).first ?? "") ?? Int.max
    }

    private func deduplicate(_ values: [GameSaveLocation]) -> [GameSaveLocation] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.relativePath.lowercased()).inserted }
    }
    private func allocatedSize(of url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        return enumerator.reduce(into: Int64(0)) { result, element in
            guard let file = element as? URL, let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .fileSizeKey]), values.isRegularFile == true else { return }
            result += Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
    }
}

// MARK: - Per-game advanced configuration

nonisolated enum ControllerInputMode: String, Codable, CaseIterable, Hashable, Sendable {
    case automatic
    case xinput
    case directInput
    case mouseKeyboardEmulation
}

nonisolated struct GameControllerProfile: Codable, Hashable, Sendable {
    var preferredControllerID: String?
    var inputMode: ControllerInputMode
    var deadZone: Double
    var desktopNavigationEnabled: Bool
    var mouseEmulationEnabled: Bool

    init(
        preferredControllerID: String? = nil,
        inputMode: ControllerInputMode = .automatic,
        deadZone: Double = 0.15,
        desktopNavigationEnabled: Bool = true,
        mouseEmulationEnabled: Bool = false
    ) {
        self.preferredControllerID = preferredControllerID
        self.inputMode = inputMode
        self.deadZone = deadZone
        self.desktopNavigationEnabled = desktopNavigationEnabled
        self.mouseEmulationEnabled = mouseEmulationEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case preferredControllerID, inputMode, deadZone, desktopNavigationEnabled, mouseEmulationEnabled
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        preferredControllerID = try values.decodeIfPresent(String.self, forKey: .preferredControllerID)
        inputMode = try values.decodeIfPresent(ControllerInputMode.self, forKey: .inputMode) ?? .automatic
        deadZone = min(max(try values.decodeIfPresent(Double.self, forKey: .deadZone) ?? 0.15, 0), 1)
        desktopNavigationEnabled = try values.decodeIfPresent(Bool.self, forKey: .desktopNavigationEnabled) ?? true
        mouseEmulationEnabled = try values.decodeIfPresent(Bool.self, forKey: .mouseEmulationEnabled) ?? false
    }

    static let `default` = GameControllerProfile(preferredControllerID: nil, inputMode: .automatic, deadZone: 0.15, desktopNavigationEnabled: true, mouseEmulationEnabled: false)
}

nonisolated struct CustomEnvironmentVariable: Codable, Hashable, Sendable, Identifiable {
    var key: String
    var value: String
    var enabled: Bool
    var id: String { key }
}

nonisolated struct EnvironmentSanitizationResult: Sendable, Hashable {
    let values: [String: String]
    let rejectedKeys: [String]
    let warnings: [String]
}

nonisolated enum EnvironmentVariableSanitizer {
    static let borealOwnedKeys: Set<String> = ["WINEPREFIX", "PATH", "WINEARCH", "WINE", "WINE64"]
    static let collisionWarningKeys: Set<String> = ["WINEDLLOVERRIDES", "WINEDLLPATH", "WINEESYNC", "WINEMSYNC"]

    static func merge(
        base: [String: String],
        custom: [CustomEnvironmentVariable],
        borealOwned: [String: String],
        developerMode: Bool = false
    ) -> EnvironmentSanitizationResult {
        var values = base
        var rejected: [String] = []
        var warnings: [String] = []
        for key in Array(values.keys) where borealOwnedKeys.contains(key.uppercased()) {
            values.removeValue(forKey: key)
        }
        for variable in custom where variable.enabled {
            let key = variable.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
                rejected.append(variable.key)
                continue
            }
            if borealOwnedKeys.contains(key.uppercased()) {
                rejected.append(key)
                warnings.append("\(key) is managed by Boreal and was not overridden.")
                continue
            }
            if collisionWarningKeys.contains(key.uppercased()) && !developerMode {
                warnings.append("\(key) may conflict with Boreal's active environment configuration.")
            }
            values[key] = variable.value
        }
        for (key, value) in borealOwned { values[key] = value }
        return EnvironmentSanitizationResult(values: values, rejectedKeys: rejected.sorted(), warnings: warnings.sorted())
    }
}

nonisolated struct DLLOverrideMergeResult: Sendable, Hashable {
    let overrides: [DLLOverride]
    let warnings: [String]
}

nonisolated enum DLLOverrideMerger {
    static func merge(managed: [DLLOverride], manual: [DLLOverride]) -> DLLOverrideMergeResult {
        var byLibrary: [String: DLLOverride] = [:]
        var warnings: [String] = []
        for override in managed {
            guard isSafeLibraryName(override.library) else {
                warnings.append("Boreal ignored an invalid managed DLL override for \(override.library).")
                continue
            }
            byLibrary[override.library.lowercased()] = override
        }
        for override in manual {
            guard isSafeLibraryName(override.library) else {
                warnings.append("Boreal ignored an invalid manual DLL override for \(override.library).")
                continue
            }
            let key = override.library.lowercased()
            if let existing = byLibrary[key], existing.mode != override.mode {
                warnings.append("\(override.library) is managed by the active graphics stack; the manual override may conflict.")
            }
            if byLibrary[key] == nil {
                byLibrary[key] = override
            }
        }
        return DLLOverrideMergeResult(overrides: byLibrary.values.sorted { $0.library.localizedStandardCompare($1.library) == .orderedAscending }, warnings: warnings.sorted())
    }

    private static func isSafeLibraryName(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
    }
}

nonisolated struct GameAdvancedConfiguration: Codable, Hashable, Sendable {
    var schemaVersion: Int = BorealStorageSchema.current
    let applicationID: UUID
    var dllOverrides: [DLLOverride]
    var environmentVariables: [CustomEnvironmentVariable]
    var manualSavePaths: [String]
    var controllerProfile: GameControllerProfile
    var updatedAt: Date

    init(
        applicationID: UUID,
        dllOverrides: [DLLOverride] = [],
        environmentVariables: [CustomEnvironmentVariable] = [],
        manualSavePaths: [String] = [],
        controllerProfile: GameControllerProfile = .default,
        updatedAt: Date = .now
    ) {
        self.applicationID = applicationID
        self.dllOverrides = dllOverrides
        self.environmentVariables = environmentVariables
        self.manualSavePaths = manualSavePaths
        self.controllerProfile = controllerProfile
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, applicationID, dllOverrides, environmentVariables, manualSavePaths, controllerProfile, updatedAt }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard schemaVersion <= BorealStorageSchema.current else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: values, debugDescription: "Unsupported game configuration schema version")
        }
        applicationID = try values.decode(UUID.self, forKey: .applicationID)
        dllOverrides = try values.decodeIfPresent([DLLOverride].self, forKey: .dllOverrides) ?? []
        environmentVariables = try values.decodeIfPresent([CustomEnvironmentVariable].self, forKey: .environmentVariables) ?? []
        manualSavePaths = try values.decodeIfPresent([String].self, forKey: .manualSavePaths) ?? []
        controllerProfile = try values.decodeIfPresent(GameControllerProfile.self, forKey: .controllerProfile) ?? .default
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}

actor GameAdvancedConfigurationStore {
    private let url: URL
    private let fileManager: FileManager
    private var values: [UUID: GameAdvancedConfiguration] = [:]
    private var loaded = false

    init(applicationSupportURL: URL, fileManager: FileManager = .default) {
        url = applicationSupportURL.appending(path: "Library/game-configurations.json")
        self.fileManager = fileManager
    }

    func configuration(for applicationID: UUID) -> GameAdvancedConfiguration {
        loadIfNeeded()
        return values[applicationID] ?? GameAdvancedConfiguration(applicationID: applicationID)
    }

    func save(_ configuration: GameAdvancedConfiguration) throws {
        loadIfNeeded()
        values[configuration.applicationID] = configuration
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Array(values.values)).write(to: url, options: .atomic)
    }

    func remove(applicationID: UUID) throws {
        loadIfNeeded()
        values[applicationID] = nil
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Array(values.values)).write(to: url, options: .atomic)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([GameAdvancedConfiguration].self, from: data) else { return }
        values = Dictionary(uniqueKeysWithValues: decoded.map { ($0.applicationID, $0) })
    }
}

// MARK: - Shader cache and storage service boundaries

nonisolated enum ShaderCacheOwner: String, Codable, Hashable, Sendable {
    case d3dMetal
    case dxmt
    case dxvk
    case vkd3d
    case wineD3D
    case runtime
    case unknown
}

nonisolated struct ShaderCacheLocation: Codable, Hashable, Sendable, Identifiable {
    let url: URL
    let owner: ShaderCacheOwner
    let safeToDelete: Bool
    var id: URL { url }
}

nonisolated protocol ShaderCacheManaging: Sendable {
    func locations(gameURL: URL?, prefixURL: URL?, backend: GraphicsBackend?) -> [ShaderCacheLocation]
    func clear(_ locations: [ShaderCacheLocation]) throws
}

nonisolated struct FileSystemShaderCacheManager: ShaderCacheManaging {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    func locations(gameURL: URL?, prefixURL: URL?, backend: GraphicsBackend?) -> [ShaderCacheLocation] {
        let roots = [gameURL, prefixURL].compactMap { $0 }
        var result: [ShaderCacheLocation] = []
        for root in roots {
            guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                let name = url.lastPathComponent.lowercased()
                guard ["shadercache", "shader_cache", "d3dscache", "dxvk-cache"].contains(name) else { continue }
                result.append(ShaderCacheLocation(url: url, owner: owner(for: backend), safeToDelete: true))
            }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.url.standardizedFileURL.path).inserted }
    }

    func clear(_ locations: [ShaderCacheLocation]) throws {
        for location in locations where location.safeToDelete && fileManager.fileExists(atPath: location.url.path) {
            try fileManager.removeItem(at: location.url)
        }
    }

    private func owner(for backend: GraphicsBackend?) -> ShaderCacheOwner {
        switch backend {
        case .d3dMetal: .d3dMetal
        case .dxmt: .dxmt
        case .dxvk: .dxvk
        case .vkd3d: .vkd3d
        case .wineD3D: .wineD3D
        default: .unknown
        }
    }
}

actor StorageAnalyzer {
    private let fileManager: FileManager
    init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    func scan(
        layout: BorealStorageLayout,
        applications: [WindowsApplication],
        storeGames: [StoreLibraryGame],
        environments: [WindowsEnvironment],
        installations: [GameInstallation]
    ) -> BorealStorageReport {
        // The existing scanner is the canonical storage ownership boundary.
        // Keep the potentially expensive traversal off MainActor behind this
        // actor while preserving its actual category rules.
        BorealStorageScanner.scan(layout: layout, applications: applications, storeGames: storeGames, environments: environments, installations: installations)
    }
}

// MARK: - Reports, benchmark and modification receipts

nonisolated struct LocalCompatibilityReport: Codable, Identifiable, Hashable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let applicationID: UUID
    let gameVersion: String?
    let runtimeID: String
    let runtimeFingerprint: String
    /// The full launch configuration fingerprint is kept separately from the
    /// runtime identity so reports can be compared after a graphics or
    /// per-game override change.
    let configurationFingerprint: String?
    let graphicsStack: GraphicsStack
    let windowsVersion: WineWindowsVersion
    let result: CompatibilityRating
    let notes: String?
    let createdAt: Date
    let traceID: OperationTraceID

    init(
        schemaVersion: Int = BorealStorageSchema.current,
        id: UUID,
        applicationID: UUID,
        gameVersion: String?,
        runtimeID: String,
        runtimeFingerprint: String,
        configurationFingerprint: String? = nil,
        graphicsStack: GraphicsStack,
        windowsVersion: WineWindowsVersion,
        result: CompatibilityRating,
        notes: String?,
        createdAt: Date,
        traceID: OperationTraceID = OperationTraceID()
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.applicationID = applicationID
        self.gameVersion = gameVersion
        self.runtimeID = runtimeID
        self.runtimeFingerprint = runtimeFingerprint
        self.configurationFingerprint = configurationFingerprint
        self.graphicsStack = graphicsStack
        self.windowsVersion = windowsVersion
        self.result = result
        self.notes = notes
        self.createdAt = createdAt
        self.traceID = traceID
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, applicationID, gameVersion, runtimeID, runtimeFingerprint
        case configurationFingerprint, graphicsStack, windowsVersion, result, notes, createdAt, traceID
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard schemaVersion <= BorealStorageSchema.current else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: values, debugDescription: "Unsupported compatibility report schema version")
        }
        id = try values.decode(UUID.self, forKey: .id)
        applicationID = try values.decode(UUID.self, forKey: .applicationID)
        gameVersion = try values.decodeIfPresent(String.self, forKey: .gameVersion)
        runtimeID = try values.decode(String.self, forKey: .runtimeID)
        runtimeFingerprint = try values.decode(String.self, forKey: .runtimeFingerprint)
        configurationFingerprint = try values.decodeIfPresent(String.self, forKey: .configurationFingerprint)
        graphicsStack = try values.decode(GraphicsStack.self, forKey: .graphicsStack)
        windowsVersion = try values.decode(WineWindowsVersion.self, forKey: .windowsVersion)
        result = try values.decode(CompatibilityRating.self, forKey: .result)
        notes = try values.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        traceID = try values.decodeIfPresent(OperationTraceID.self, forKey: .traceID) ?? OperationTraceID()
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(applicationID, forKey: .applicationID)
        try values.encodeIfPresent(gameVersion, forKey: .gameVersion)
        try values.encode(runtimeID, forKey: .runtimeID)
        try values.encode(runtimeFingerprint, forKey: .runtimeFingerprint)
        try values.encodeIfPresent(configurationFingerprint, forKey: .configurationFingerprint)
        try values.encode(graphicsStack, forKey: .graphicsStack)
        try values.encode(windowsVersion, forKey: .windowsVersion)
        try values.encode(result, forKey: .result)
        try values.encodeIfPresent(notes, forKey: .notes)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(traceID, forKey: .traceID)
    }
}

nonisolated enum CompatibilityReportError: LocalizedError, Sendable {
    case noInstalledRuntime
    case noGraphicsStack

    var errorDescription: String? {
        switch self {
        case .noInstalledRuntime: "The compatibility report needs an installed runtime fingerprint."
        case .noGraphicsStack: "The compatibility report needs a resolved graphics stack."
        }
    }
}

nonisolated protocol CompatibilityReportProviding: Sendable {
    func reports(for applicationID: UUID) async -> [LocalCompatibilityReport]
    func save(_ report: LocalCompatibilityReport) async throws
}

actor CompatibilityReportStore: CompatibilityReportProviding {
    private let url: URL
    private let fileManager: FileManager
    private var loaded = false
    private var values: [LocalCompatibilityReport] = []

    init(applicationSupportURL: URL, fileManager: FileManager = .default) {
        url = applicationSupportURL.appending(path: "Library/compatibility-reports.json")
        self.fileManager = fileManager
    }

    func reports(for applicationID: UUID) async -> [LocalCompatibilityReport] {
        loadIfNeeded()
        return values.filter { $0.applicationID == applicationID }.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ report: LocalCompatibilityReport) async throws {
        loadIfNeeded()
        values.append(report)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(values).write(to: url, options: .atomic)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([LocalCompatibilityReport].self, from: data) else { return }
        values = decoded
    }
}

nonisolated struct BenchmarkSession: Codable, Identifiable, Hashable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let applicationID: UUID
    let configurationFingerprint: String
    let startedAt: Date
    let duration: TimeInterval
    let averageFPS: Double?
    let onePercentLow: Double?
    let averageFrameTime: Double?
    let crashOccurred: Bool
    let traceID: OperationTraceID

    init(
        schemaVersion: Int = BorealStorageSchema.current,
        id: UUID,
        applicationID: UUID,
        configurationFingerprint: String,
        startedAt: Date,
        duration: TimeInterval,
        averageFPS: Double?,
        onePercentLow: Double?,
        averageFrameTime: Double?,
        crashOccurred: Bool,
        traceID: OperationTraceID
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.applicationID = applicationID
        self.configurationFingerprint = configurationFingerprint
        self.startedAt = startedAt
        self.duration = duration
        self.averageFPS = averageFPS
        self.onePercentLow = onePercentLow
        self.averageFrameTime = averageFrameTime
        self.crashOccurred = crashOccurred
        self.traceID = traceID
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, applicationID, configurationFingerprint, startedAt, duration
        case averageFPS, onePercentLow, averageFrameTime, crashOccurred, traceID
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard schemaVersion <= BorealStorageSchema.current else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: values, debugDescription: "Unsupported benchmark schema version")
        }
        id = try values.decode(UUID.self, forKey: .id)
        applicationID = try values.decode(UUID.self, forKey: .applicationID)
        configurationFingerprint = try values.decode(String.self, forKey: .configurationFingerprint)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        duration = try values.decode(TimeInterval.self, forKey: .duration)
        averageFPS = try values.decodeIfPresent(Double.self, forKey: .averageFPS)
        onePercentLow = try values.decodeIfPresent(Double.self, forKey: .onePercentLow)
        averageFrameTime = try values.decodeIfPresent(Double.self, forKey: .averageFrameTime)
        crashOccurred = try values.decode(Bool.self, forKey: .crashOccurred)
        traceID = try values.decodeIfPresent(OperationTraceID.self, forKey: .traceID) ?? OperationTraceID()
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(applicationID, forKey: .applicationID)
        try values.encode(configurationFingerprint, forKey: .configurationFingerprint)
        try values.encode(startedAt, forKey: .startedAt)
        try values.encode(duration, forKey: .duration)
        try values.encodeIfPresent(averageFPS, forKey: .averageFPS)
        try values.encodeIfPresent(onePercentLow, forKey: .onePercentLow)
        try values.encodeIfPresent(averageFrameTime, forKey: .averageFrameTime)
        try values.encode(crashOccurred, forKey: .crashOccurred)
        try values.encode(traceID, forKey: .traceID)
    }
}

nonisolated struct ConfigurationFingerprint: Hashable, Sendable {
    static func make(
        runtimeFingerprint: String,
        graphicsStack: GraphicsStack,
        componentVersions: [String: String],
        prefixMode: WinePrefixMode,
        windowsVersion: WineWindowsVersion,
        dependencies: [RuntimeDependency],
        dllOverrides: [DLLOverride],
        environmentVariables: [CustomEnvironmentVariable],
        upscalingConfiguration: String
    ) -> String {
        let components = componentVersions.keys.sorted().map { "\($0)=\(componentVersions[$0] ?? "")" }
        let overrides = dllOverrides.sorted { $0.library < $1.library }.map { "\($0.library)=\($0.mode.rawValue)" }
        let variables = environmentVariables.filter(\.enabled).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        let value = [
            "runtime=\(runtimeFingerprint)",
            "graphics=\(graphicsStack.backend.rawValue)",
            "api=\(graphicsStack.supportedAPIs.map(\.rawValue).sorted().joined(separator: ","))",
            "components=\(components.joined(separator: ","))",
            "prefix=\(prefixMode.rawValue)",
            "windows=\(windowsVersion.rawValue)",
            "dependencies=\(dependencies.map(\.rawValue).sorted().joined(separator: ","))",
            "overrides=\(overrides.joined(separator: ","))",
            "variables=\(variables.joined(separator: ","))",
            "upscaling=\(upscalingConfiguration)"
        ].joined(separator: "|")
        return sha256Hex(Data(value.utf8))
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated struct ManagedFileChange: Codable, Hashable, Sendable {
    let relativePath: String
    let action: String
    let checksum: String?
}

nonisolated struct ManagedGameModification: Codable, Identifiable, Hashable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let applicationID: UUID
    let name: String
    let version: String?
    let installedAt: Date
    let installedFiles: [ManagedFileChange]
    let backupReference: UUID?

    init(
        schemaVersion: Int = BorealStorageSchema.current,
        id: UUID,
        applicationID: UUID,
        name: String,
        version: String?,
        installedAt: Date,
        installedFiles: [ManagedFileChange],
        backupReference: UUID?
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.applicationID = applicationID
        self.name = name
        self.version = version
        self.installedAt = installedAt
        self.installedFiles = installedFiles
        self.backupReference = backupReference
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, applicationID, name, version, installedAt, installedFiles, backupReference
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard schemaVersion <= BorealStorageSchema.current else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: values, debugDescription: "Unsupported modification receipt schema version")
        }
        id = try values.decode(UUID.self, forKey: .id)
        applicationID = try values.decode(UUID.self, forKey: .applicationID)
        name = try values.decode(String.self, forKey: .name)
        version = try values.decodeIfPresent(String.self, forKey: .version)
        installedAt = try values.decode(Date.self, forKey: .installedAt)
        installedFiles = try values.decodeIfPresent([ManagedFileChange].self, forKey: .installedFiles) ?? []
        backupReference = try values.decodeIfPresent(UUID.self, forKey: .backupReference)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(applicationID, forKey: .applicationID)
        try values.encode(name, forKey: .name)
        try values.encodeIfPresent(version, forKey: .version)
        try values.encode(installedAt, forKey: .installedAt)
        try values.encode(installedFiles, forKey: .installedFiles)
        try values.encodeIfPresent(backupReference, forKey: .backupReference)
    }
}

// MARK: - Small collection helpers

private extension Array where Element == URL {
    var deduplicatedURLs: [URL] {
        var seen = Set<String>()
        return filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
