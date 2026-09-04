import Foundation

nonisolated enum RuntimeArchitecture: String, Codable, Sendable { case x86_64, arm64 }
nonisolated enum RuntimeChannel: String, Codable, Sendable {
    case developer, preview, stable

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "developer", "devel": self = .developer
        case "preview", "staging": self = .preview
        case "stable": self = .stable
        default: throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Unknown runtime channel: \(value)")
        }
    }
}
nonisolated enum RuntimeRequirement: String, Codable, Sendable, Hashable { case rosetta2, gStreamerFramework }
nonisolated enum RuntimeOrigin: String, Codable, Sendable, Hashable { case catalog, localImport }
nonisolated enum RuntimeEngine: String, Codable, Sendable, Hashable {
    case wine
    case gamePortingToolkit

    var displayName: String {
        switch self {
        case .wine: "Wine"
        case .gamePortingToolkit: "Game Porting Toolkit"
        }
    }

    var graphicsName: String { self == .gamePortingToolkit ? "D3DMetal" : "WineD3D" }
}

nonisolated struct RuntimeFeatures: Codable, Sendable, Hashable {
    var wow64: Bool
    var wineMono: Bool
    var wineGecko: Bool
    var d3dmetal: Bool
    var dxmt: Bool
    var dxvk: Bool = false
    var vkd3d: Bool = false

    private enum CodingKeys: String, CodingKey {
        case wow64, wineMono, wineGecko, d3dmetal, dxmt, dxvk, vkd3d
    }

    init(wow64: Bool, wineMono: Bool, wineGecko: Bool, d3dmetal: Bool, dxmt: Bool, dxvk: Bool = false, vkd3d: Bool = false) {
        self.wow64 = wow64
        self.wineMono = wineMono
        self.wineGecko = wineGecko
        self.d3dmetal = d3dmetal
        self.dxmt = dxmt
        self.dxvk = dxvk
        self.vkd3d = vkd3d
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        wow64 = try values.decodeIfPresent(Bool.self, forKey: .wow64) ?? false
        wineMono = try values.decodeIfPresent(Bool.self, forKey: .wineMono) ?? false
        wineGecko = try values.decodeIfPresent(Bool.self, forKey: .wineGecko) ?? false
        d3dmetal = try values.decodeIfPresent(Bool.self, forKey: .d3dmetal) ?? false
        dxmt = try values.decodeIfPresent(Bool.self, forKey: .dxmt) ?? false
        dxvk = try values.decodeIfPresent(Bool.self, forKey: .dxvk) ?? false
        vkd3d = try values.decodeIfPresent(Bool.self, forKey: .vkd3d) ?? false
    }
}

nonisolated enum RuntimeComponent: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case dxvk
    case vkd3d

    var id: String { rawValue }
    var displayName: String { self == .dxvk ? "DXVK" : "VKD3D-Proton" }
    var directoryName: String { self == .dxvk ? "DXVK" : "VKD3D" }
}

/// Windows redistributables belong to a mutable game environment, never to
/// the immutable runtime package or the user's global Wine prefix.
nonisolated enum RuntimeDependency: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case directXRuntime, vc2010, vc2015To2022, xact, xinput, dotNetFramework, physX
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .directXRuntime: "DirectX runtime"
        case .vc2010: "VC++ 2010"
        case .vc2015To2022: "VC++ 2015–2022"
        case .xact: "XACT"
        case .xinput: "XInput"
        case .dotNetFramework: ".NET Framework"
        case .physX: "PhysX"
        }
    }
    var winetricksVerb: String {
        switch self {
        case .directXRuntime: "d3dx9"
        case .vc2010: "vcrun2010"
        case .vc2015To2022: "vcrun2019"
        case .xact: "xact"
        case .xinput: "xinput"
        case .dotNetFramework: "dotnet48"
        case .physX: "physx"
        }
    }
    var detectionLibraries: [String] {
        switch self {
        case .directXRuntime: ["d3dx9_43.dll", "d3dcompiler_43.dll"]
        case .vc2010: ["msvcp100.dll", "msvcr100.dll"]
        case .vc2015To2022: ["msvcp140.dll", "vcruntime140.dll"]
        case .xact: ["xactengine3_7.dll"]
        case .xinput: ["xinput1_3.dll", "xinput1_4.dll"]
        case .dotNetFramework: ["mscoree.dll"]
        case .physX: ["PhysXLoader.dll"]
        }
    }
}

nonisolated enum RuntimeDependencyState: String, Codable, Sendable, Hashable {
    case installed, missing, installing, failed
}

nonisolated enum RuntimeDependencyRecommendation: String, Codable, Sendable, Hashable {
    case required, recommended, optional
}

nonisolated struct RuntimeDependencyStatus: Identifiable, Codable, Sendable, Hashable {
    var id: RuntimeDependency { dependency }
    let dependency: RuntimeDependency
    var state: RuntimeDependencyState
    var detail: String?
    var recommendation: RuntimeDependencyRecommendation = .optional
}

nonisolated enum RuntimeDependencyResolver {
    static func resolve(executableURL: URL?) -> [RuntimeDependency: (RuntimeDependencyRecommendation, String)] {
        var result: [RuntimeDependency: (RuntimeDependencyRecommendation, String)] = [
            .vc2015To2022: (.recommended, "Common runtime for modern Windows games"),
            .xinput: (.recommended, "Common controller API for Windows games"),
            .directXRuntime: (.optional, "Install only when the game needs legacy DirectX components"),
            .vc2010: (.optional, "Install only for games built with Visual C++ 2010"),
            .xact: (.optional, "Install only for games using legacy XACT audio"),
            .dotNetFramework: (.optional, "Install only when this game explicitly requires .NET Framework"),
            .physX: (.optional, "Install only for games that use NVIDIA PhysX")
        ]
        guard let executableURL,
              let data = try? Data(contentsOf: executableURL, options: [.mappedIfSafe]),
              !data.isEmpty else { return result }

        // PE import names are ASCII. Scanning the memory-mapped bytes also
        // catches delay-loaded imports without executing or modifying the game.
        func containsImport(_ name: String) -> Bool {
            let lower = Data(name.lowercased().utf8)
            let upper = Data(name.uppercased().utf8)
            return data.range(of: lower) != nil || data.range(of: upper) != nil
        }
        let evidence: [(RuntimeDependency, [String], String)] = [
            (.directXRuntime, ["d3dx9_", "d3dcompiler_43.dll"], "Required by this executable's legacy DirectX imports"),
            (.vc2010, ["msvcp100.dll", "msvcr100.dll"], "Required by this executable's Visual C++ 2010 imports"),
            (.vc2015To2022, ["msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"], "Required by this executable's Visual C++ runtime imports"),
            (.xact, ["xactengine"], "Required by this executable's XACT audio import"),
            (.xinput, ["xinput1_3.dll", "xinput1_4.dll", "xinput9_1_0.dll"], "Required by this executable's controller API import"),
            (.dotNetFramework, ["mscoree.dll"], "Required by this managed .NET executable"),
            (.physX, ["physxloader.dll", "physx3"], "Required by this executable's NVIDIA PhysX import")
        ]
        for (dependency, names, detail) in evidence where names.contains(where: containsImport) {
            result[dependency] = (.required, detail)
        }
        return result
    }
}

nonisolated struct RuntimeComponentReceipt: Codable, Sendable, Hashable {
    let component: RuntimeComponent
    let version: String
    let sourceRepository: String
    let installedAt: Date
}

nonisolated struct RuntimeComponentUpdate: Identifiable, Sendable, Hashable {
    enum State: Sendable, Hashable { case notInstalled, current, available }
    var id: String { "\(runtimeID):\(component.rawValue)" }
    let runtimeID: String
    let runtimeName: String
    let component: RuntimeComponent
    let installedVersion: String?
    let latestVersion: String
    let state: State
}

nonisolated enum WindowsExecutableArchitecture: Equatable, Sendable {
    case x86, x86_64, unknown

    static func inspect(_ url: URL) -> Self {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 64),
              header.count >= 64,
              header[0] == 0x4D,
              header[1] == 0x5A else { return .unknown }

        let peOffset = Int(header[60])
            | (Int(header[61]) << 8)
            | (Int(header[62]) << 16)
            | (Int(header[63]) << 24)
        guard peOffset >= 0,
              (try? handle.seek(toOffset: UInt64(peOffset))) != nil,
              let peHeader = try? handle.read(upToCount: 26),
              peHeader.count >= 26,
              Array(peHeader.prefix(4)) == [0x50, 0x45, 0x00, 0x00] else { return .unknown }

        let optionalHeaderMagic = UInt16(peHeader[24]) | (UInt16(peHeader[25]) << 8)
        switch optionalHeaderMagic {
        case 0x10B: return .x86
        case 0x20B: return .x86_64
        default: return .unknown
        }
    }
}

nonisolated struct RuntimeArtifact: Codable, Sendable, Hashable {
    let url: URL
    let sha256: String
    let compressedSize: Int64
}

nonisolated struct RuntimeComponents: Codable, Sendable, Hashable {
    var mono: String? = nil
    var gecko: String? = nil
}

nonisolated struct RuntimeLayout: Codable, Sendable, Hashable {
    var wineExecutable: String
    var wineServerExecutable: String
    var wineBootExecutable: String
    var dependenciesDirectory: String
    var supportDirectory: String
    var licensesDirectory: String
    var noticesFile: String
    var sbomFile: String

    static let canonical = RuntimeLayout(
        wineExecutable: "Runtime/Wine.app/Contents/Resources/wine/bin/wine",
        wineServerExecutable: "Runtime/Wine.app/Contents/Resources/wine/bin/wineserver",
        wineBootExecutable: "Runtime/Wine.app/Contents/Resources/wine/bin/wineboot",
        dependenciesDirectory: "Dependencies",
        supportDirectory: "Support",
        licensesDirectory: "Licenses",
        noticesFile: "Licenses/THIRD_PARTY_NOTICES.txt",
        sbomFile: "SBOM.spdx.json"
    )
}

nonisolated struct RuntimePackageManifest: Codable, Sendable, Hashable {
    let schemaVersion: Int
    let id: String
    let displayName: String
    let wineVersion: String
    let borealRevision: Int
    let architecture: RuntimeArchitecture
    let minimumMacOS: String
    let requiresRosetta: Bool
    let channel: RuntimeChannel
    let features: RuntimeFeatures
    let components: RuntimeComponents
    let layout: RuntimeLayout
}

nonisolated struct BorealRuntime: Codable, Identifiable, Sendable, Hashable {
    let schemaVersion: Int
    let id: String
    let displayName: String
    let wineVersion: String
    let borealRevision: Int
    let architecture: RuntimeArchitecture
    let minimumMacOS: String
    let channel: RuntimeChannel
    let requirements: Set<RuntimeRequirement>
    let features: RuntimeFeatures
    let components: RuntimeComponents
    let layout: RuntimeLayout
    let artifact: RuntimeArtifact

    var packageManifest: RuntimePackageManifest {
        RuntimePackageManifest(
            schemaVersion: schemaVersion,
            id: id,
            displayName: displayName,
            wineVersion: wineVersion,
            borealRevision: borealRevision,
            architecture: architecture,
            minimumMacOS: minimumMacOS,
            requiresRosetta: requirements.contains(.rosetta2),
            channel: channel,
            features: features,
            components: components,
            layout: layout
        )
    }

    init(
        schemaVersion: Int,
        id: String,
        displayName: String,
        wineVersion: String,
        borealRevision: Int = 1,
        architecture: RuntimeArchitecture,
        minimumMacOS: String,
        channel: RuntimeChannel,
        requirements: Set<RuntimeRequirement>,
        features: RuntimeFeatures,
        components: RuntimeComponents = RuntimeComponents(),
        layout: RuntimeLayout = .canonical,
        artifact: RuntimeArtifact
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.wineVersion = wineVersion
        self.borealRevision = borealRevision
        self.architecture = architecture
        self.minimumMacOS = minimumMacOS
        self.channel = channel
        self.requirements = requirements
        self.features = features
        self.components = components
        self.layout = layout
        self.artifact = artifact
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, displayName, wineVersion, borealRevision, architecture, minimumMacOS, requiresRosetta, channel, requirements, features, components, layout, artifact
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        id = try values.decode(String.self, forKey: .id)
        displayName = try values.decode(String.self, forKey: .displayName)
        wineVersion = try values.decode(String.self, forKey: .wineVersion)
        borealRevision = try values.decodeIfPresent(Int.self, forKey: .borealRevision) ?? 1
        architecture = try values.decode(RuntimeArchitecture.self, forKey: .architecture)
        minimumMacOS = try values.decode(String.self, forKey: .minimumMacOS)
        channel = try values.decode(RuntimeChannel.self, forKey: .channel)
        var decodedRequirements = try values.decodeIfPresent(Set<RuntimeRequirement>.self, forKey: .requirements) ?? []
        if try values.decodeIfPresent(Bool.self, forKey: .requiresRosetta) == true { decodedRequirements.insert(.rosetta2) }
        requirements = decodedRequirements
        features = try values.decode(RuntimeFeatures.self, forKey: .features)
        components = try values.decodeIfPresent(RuntimeComponents.self, forKey: .components) ?? RuntimeComponents()
        layout = try values.decodeIfPresent(RuntimeLayout.self, forKey: .layout) ?? .canonical
        artifact = try values.decode(RuntimeArtifact.self, forKey: .artifact)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(displayName, forKey: .displayName)
        try values.encode(wineVersion, forKey: .wineVersion)
        try values.encode(borealRevision, forKey: .borealRevision)
        try values.encode(architecture, forKey: .architecture)
        try values.encode(minimumMacOS, forKey: .minimumMacOS)
        try values.encode(requirements.contains(.rosetta2), forKey: .requiresRosetta)
        try values.encode(channel, forKey: .channel)
        try values.encode(requirements, forKey: .requirements)
        try values.encode(features, forKey: .features)
        try values.encode(components, forKey: .components)
        try values.encode(layout, forKey: .layout)
        try values.encode(artifact, forKey: .artifact)
    }
}

nonisolated struct InstalledRuntime: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let displayName: String
    let wineVersion: String
    let rootURL: URL
    let wineExecutable: URL
    let wineServerExecutable: URL
    let wineBootExecutable: URL
    let architecture: RuntimeArchitecture
    let requirements: Set<RuntimeRequirement>
    var origin: RuntimeOrigin? = nil
    var engine: RuntimeEngine? = nil
    var features: RuntimeFeatures? = nil

    var resolvedEngine: RuntimeEngine {
        engine ?? (features?.d3dmetal == true ? .gamePortingToolkit : .wine)
    }

    var runtimeDescription: String { "\(displayName) · \(resolvedEngine.displayName) \(wineVersion)" }
    var graphicsName: String { resolvedEngine.graphicsName }
}

nonisolated struct LocalRuntimeCandidate: Identifiable, Sendable, Hashable {
    let id: String
    let displayName: String
    let wineVersion: String
    let appURL: URL
    let architecture: RuntimeArchitecture
    let requirements: Set<RuntimeRequirement>
    let minimumMacOS: String
    let estimatedSize: Int64?
    var engine: RuntimeEngine = .wine
    var features: RuntimeFeatures = RuntimeFeatures(wow64: false, wineMono: false, wineGecko: false, d3dmetal: false, dxmt: false)
    var layout: RuntimeLayout = .canonical
}

nonisolated struct RuntimeValidation: Sendable, Equatable {
    var detectedWineVersion: String?
    var versionMatchesManifest: Bool
    var missingPaths: [String]
    var unmetRequirements: Set<RuntimeRequirement>
    var executablePaths: [String]
    var isReady: Bool { missingPaths.isEmpty && unmetRequirements.isEmpty && detectedWineVersion != nil && versionMatchesManifest }
}

nonisolated enum RuntimeManagerError: LocalizedError, Sendable {
    case invalidManifest
    case manifestSignatureInvalid
    case alreadyInstalled(String)
    case checksumMismatch(expected: String, actual: String)
    case unsupportedArchive
    case runtimeLayoutNotFound
    case packageManifestMismatch
    case unsafeArchive(String)
    case nonSelfContained(RuntimeRequirement)
    case validationFailed(RuntimeValidation)
    case requirementMissing(RuntimeRequirement)
    case downloadFailed(String)
    case localRuntimeInvalid(String)
    case incompatible32BitExecutable(runtime: String)
    case incompatible64BitExecutable

    var errorDescription: String? {
        switch self {
        case .invalidManifest: return "The runtime manifest is invalid."
        case .manifestSignatureInvalid: return "The runtime manifest signature is invalid."
        case .alreadyInstalled(let id): return "Runtime \(id) is already installed."
        case .checksumMismatch: return "Runtime verification failed because its SHA-256 checksum does not match."
        case .unsupportedArchive: return "The runtime archive format is not supported."
        case .runtimeLayoutNotFound: return "Boreal couldn’t locate Wine inside the runtime package."
        case .packageManifestMismatch: return "The runtime package manifest does not match the signed catalog entry."
        case .unsafeArchive(let path): return "The runtime archive contains an unsafe path: \(path)"
        case .nonSelfContained(.gStreamerFramework): return "This runtime depends on a system GStreamer installation and is not self-contained."
        case .nonSelfContained(.rosetta2): return "Rosetta is a platform requirement, not a bundled runtime dependency."
        case .validationFailed(let validation):
            var details: [String] = []
            if !validation.missingPaths.isEmpty {
                details.append("Missing or incomplete: \(validation.missingPaths.joined(separator: ", "))")
            }
            if !validation.unmetRequirements.isEmpty {
                let requirements = validation.unmetRequirements.map {
                    switch $0 {
                    case .rosetta2: "Rosetta 2"
                    case .gStreamerFramework: "GStreamer.framework"
                    }
                }.sorted()
                details.append("Unmet requirements: \(requirements.joined(separator: ", "))")
            }
            if validation.detectedWineVersion == nil {
                details.append("Wine did not return a version.")
            } else if !validation.versionMatchesManifest {
                details.append("Detected Wine version does not match the imported app.")
            }
            return details.isEmpty
                ? "The installed runtime did not pass validation."
                : "The installed runtime did not pass validation. \(details.joined(separator: " "))"
        case .requirementMissing(.rosetta2): return "Rosetta 2 is required by this runtime."
        case .requirementMissing(.gStreamerFramework): return "GStreamer.framework is required by this development runtime."
        case .downloadFailed(let reason): return "Runtime download failed: \(reason)"
        case .localRuntimeInvalid(let reason): return "The installed Wine app can’t be imported: \(reason)"
        case .incompatible32BitExecutable(let runtime): return "This game is 32-bit, but \(runtime) does not provide WoW64 support. Use a Wine runtime that supports 32-bit Windows applications."
        case .incompatible64BitExecutable: return "This application is 64-bit and cannot run in a 32-bit Wine prefix. Choose the Win64 architecture."
        }
    }
}

nonisolated protocol RuntimeManaging: Sendable {
    func availableRuntimes() async throws -> [BorealRuntime]
    func installedRuntimes() async throws -> [InstalledRuntime]
    func localRuntimeCandidates() async -> [LocalRuntimeCandidate]
    func importLocalRuntime(_ candidate: LocalRuntimeCandidate) async throws -> InstalledRuntime
    func install(_ runtime: BorealRuntime) async throws -> InstalledRuntime
    func validate(_ runtime: InstalledRuntime) async throws -> RuntimeValidation
    func remove(_ runtime: InstalledRuntime) async throws
    func installGraphicsComponent(
        _ backend: WineGraphicsBackend,
        from source: URL,
        into runtimeID: String
    ) async throws -> InstalledRuntime
    func downloadAndInstallGraphicsComponent(
        _ backend: WineGraphicsBackend,
        into runtimeID: String
    ) async throws -> InstalledRuntime
    func componentUpdates() async throws -> [RuntimeComponentUpdate]
    func downloadAndInstallComponent(_ component: RuntimeComponent, into runtimeID: String) async throws -> InstalledRuntime
}

nonisolated extension RuntimeManaging {
    func componentUpdates() async throws -> [RuntimeComponentUpdate] { [] }
    func downloadAndInstallComponent(_ component: RuntimeComponent, into runtimeID: String) async throws -> InstalledRuntime {
        if component == .dxvk { return try await downloadAndInstallGraphicsComponent(.dxvk, into: runtimeID) }
        throw CocoaError(.featureUnsupported)
    }
    func installGraphicsComponent(
        _ backend: WineGraphicsBackend,
        from source: URL,
        into runtimeID: String
    ) async throws -> InstalledRuntime {
        throw CocoaError(.featureUnsupported)
    }

    func downloadAndInstallGraphicsComponent(
        _ backend: WineGraphicsBackend,
        into runtimeID: String
    ) async throws -> InstalledRuntime {
        throw CocoaError(.featureUnsupported)
    }
}
