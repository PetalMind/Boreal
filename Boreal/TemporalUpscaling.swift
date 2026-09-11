import CryptoKit
import Foundation

// MARK: - Detection

nonisolated enum CapabilityConfidence: String, Codable, CaseIterable, Sendable, Hashable {
    case low
    case medium
    case high
    case verified
}

nonisolated enum UpscalerDetectionSource: String, Codable, CaseIterable, Sendable, Hashable {
    case fileName
    case peVersionMetadata
    case peImports
    case exportedSymbols
    case peArchitecture
    case knownGameProfile
    case runtimePayload
    case managedComponentStore
}

nonisolated enum TemporalUpscalerKind: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case dlss
    case fsr
    case xess

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dlss: "NVIDIA DLSS / NGX"
        case .fsr: "AMD FSR 2+ / FSR 3+"
        case .xess: "Intel XeSS"
        }
    }
}

nonisolated struct UpscalerDetectionEvidence: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let source: UpscalerDetectionSource
    let path: String
    let detail: String
    let accepted: Bool

    init(
        id: UUID = UUID(),
        source: UpscalerDetectionSource,
        path: String,
        detail: String,
        accepted: Bool = true
    ) {
        self.id = id
        self.source = source
        self.path = path
        self.detail = detail
        self.accepted = accepted
    }
}

nonisolated struct TemporalUpscalerCapability: Codable, Sendable, Hashable {
    let kind: TemporalUpscalerKind
    let detected: Bool
    let version: String?
    let confidence: CapabilityConfidence
    let sources: [UpscalerDetectionSource]
    let evidence: [UpscalerDetectionEvidence]
    let fileURLs: [URL]
}

nonisolated enum FrameGenerationSupport: String, Codable, CaseIterable, Sendable, Hashable {
    case unavailable
    case candidate
    case experimental
    case verified
}

nonisolated struct FrameGenerationCapability: Codable, Sendable, Hashable {
    let support: FrameGenerationSupport
    let evidence: [UpscalerDetectionEvidence]
}

nonisolated struct AntiCheatDetection: Codable, Sendable, Hashable {
    let detected: Bool
    let markers: [String]
    let evidence: [UpscalerDetectionEvidence]

    static let unknown = AntiCheatDetection(detected: false, markers: [], evidence: [])
}

nonisolated struct GameUpscalingCapabilities: Codable, Sendable, Hashable {
    let gameRoot: URL
    let analyzedAt: Date
    let dlss: TemporalUpscalerCapability?
    let fsr: TemporalUpscalerCapability?
    let xess: TemporalUpscalerCapability?
    let frameGeneration: FrameGenerationCapability
    let antiCheat: AntiCheatDetection

    var detectedTemporalInterfaces: [TemporalUpscalerCapability] {
        [dlss, fsr, xess].compactMap { $0 }.filter(\.detected)
    }

    var hasTemporalInterface: Bool { !detectedTemporalInterfaces.isEmpty }
}

/// A small PE reader used only for metadata and import/export inspection. It
/// never maps a Windows image for execution and never invokes a game helper.
nonisolated struct WindowsPEInspection: Sendable, Hashable {
    let isPE: Bool
    let architecture: WindowsExecutableArchitecture
    let version: String?
    let imports: Set<String>
    let exports: Set<String>

    static let unknown = WindowsPEInspection(
        isPE: false,
        architecture: .unknown,
        version: nil,
        imports: [],
        exports: []
    )

    static func inspect(_ url: URL, fileManager: FileManager = .default) -> Self {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]), data.count >= 64 else {
            return .unknown
        }
        guard u32(data, at: 0) & 0xffff == 0x5a4d else { return .unknown }
        guard let peOffset = intOffset(data, at: 0x3c), peOffset >= 0,
              let peHeaderEnd = checkedAdd(peOffset, 26),
              peHeaderEnd <= data.count,
              u32(data, at: peOffset) == 0x00004550 else { return .unknown }

        let fileHeader = peOffset + 4
        let machine = u16(data, at: fileHeader)
        let sectionCount = Int(exactly: u16(data, at: fileHeader + 2)) ?? 0
        let optionalSize = Int(exactly: u16(data, at: fileHeader + 16)) ?? 0
        let optionalHeader = fileHeader + 20
        guard let optionalHeaderEnd = checkedAdd(optionalHeader, optionalSize),
              optionalHeaderEnd <= data.count,
              optionalSize >= 32 else { return .unknown }
        let magic = u16(data, at: optionalHeader)
        let architecture: WindowsExecutableArchitecture = switch machine {
        case 0x014c: .x86
        case 0x8664: .x86_64
        default: .unknown
        }
        guard magic == 0x010b || magic == 0x020b else {
            return WindowsPEInspection(isPE: true, architecture: architecture, version: extractVersion(from: data), imports: [], exports: [])
        }

        guard let dataDirectoryOffset = checkedAdd(optionalHeader, magic == 0x020b ? 112 : 96),
              let numberOfDirectoriesOffset = checkedAdd(optionalHeader, magic == 0x020b ? 108 : 92),
              let sectionTable = checkedAdd(optionalHeader, optionalSize) else { return .unknown }
        let directoryCount = Int(exactly: u32(data, at: numberOfDirectoriesOffset)) ?? 0
        var sections: [PESection] = []
        if sectionCount > 0,
           let sectionTableSize = checkedMultiply(sectionCount, 40),
           let sectionTableEnd = checkedAdd(sectionTable, sectionTableSize),
           sectionTableEnd <= data.count {
            for index in 0..<sectionCount {
                guard let offset = checkedAdd(sectionTable, index * 40) else { break }
                sections.append(PESection(
                    virtualAddress: u32(data, at: offset + 12),
                    virtualSize: u32(data, at: offset + 8),
                    rawAddress: u32(data, at: offset + 20),
                    rawSize: u32(data, at: offset + 16)
                ))
            }
        }

        func directory(_ index: Int) -> (rva: UInt32, size: UInt32)? {
            guard index >= 0, index < directoryCount,
                  let entryEnd = checkedAdd(dataDirectoryOffset, (index + 1) * 8),
                  entryEnd <= data.count,
                  let offset = checkedAdd(dataDirectoryOffset, index * 8) else { return nil }
            let rva = u32(data, at: offset)
            let size = u32(data, at: offset + 4)
            return rva == 0 ? nil : (rva, size)
        }

        let imports = directory(1).map { parseImports(data: data, directory: $0, sections: sections, architecture: architecture) } ?? []
        let exports = directory(0).map { parseExports(data: data, directory: $0, sections: sections) } ?? []
        return WindowsPEInspection(
            isPE: true,
            architecture: architecture,
            version: extractVersion(from: data),
            imports: imports,
            exports: exports
        )
    }

    private struct PESection {
        let virtualAddress: UInt32
        let virtualSize: UInt32
        let rawAddress: UInt32
        let rawSize: UInt32

        func fileOffset(for rva: UInt32) -> Int? {
            let size = max(virtualSize, rawSize)
            guard rva >= virtualAddress, rva - virtualAddress < size else { return nil }
            let offset = UInt64(rawAddress) + UInt64(rva - virtualAddress)
            return offset <= UInt64(Int.max) ? Int(offset) : nil
        }
    }

    private static func parseImports(
        data: Data,
        directory: (rva: UInt32, size: UInt32),
        sections: [PESection],
        architecture: WindowsExecutableArchitecture
    ) -> Set<String> {
        guard let directoryOffset = fileOffset(directory.rva, sections: sections),
              let directorySize = Int(exactly: directory.size),
              let directoryEnd = checkedAdd(directoryOffset, directorySize) else { return [] }
        var result = Set<String>()
        var cursor = directoryOffset
        let end = min(data.count, directoryEnd)
        while let recordEnd = checkedAdd(cursor, 20), recordEnd <= end {
            let originalThunk = u32(data, at: cursor)
            let nameRVA = u32(data, at: cursor + 12)
            let firstThunk = u32(data, at: cursor + 16)
            if originalThunk == 0 && nameRVA == 0 && firstThunk == 0 { break }
            if let nameOffset = fileOffset(nameRVA, sections: sections), let name = asciiString(data, at: nameOffset) {
                result.insert(name.lowercased())
            }
            guard let nextCursor = checkedAdd(cursor, 20) else { break }
            cursor = nextCursor
        }
        // The architecture argument is deliberately consumed to keep this
        // parser's contract explicit: imports are metadata, not code loading.
        _ = architecture
        return result
    }

    private static func parseExports(
        data: Data,
        directory: (rva: UInt32, size: UInt32),
        sections: [PESection]
    ) -> Set<String> {
        guard let offset = fileOffset(directory.rva, sections: sections),
              let exportHeaderEnd = checkedAdd(offset, 40),
              exportHeaderEnd <= data.count,
              let count = Int(exactly: u32(data, at: offset + 24)) else { return [] }
        let namesRVA = u32(data, at: offset + 32)
        guard count > 0, count < 100_000, let namesOffset = fileOffset(namesRVA, sections: sections) else { return [] }
        var result = Set<String>()
        for index in 0..<count {
            guard let pointer = checkedAdd(namesOffset, index * 4),
                  let pointerEnd = checkedAdd(pointer, 4),
                  pointerEnd <= data.count,
                  let nameOffset = fileOffset(u32(data, at: pointer), sections: sections),
                  let name = asciiString(data, at: nameOffset) else { continue }
            result.insert(name)
        }
        return result
    }

    private static func fileOffset(_ rva: UInt32, sections: [PESection]) -> Int? {
        sections.first { $0.fileOffset(for: rva) != nil }?.fileOffset(for: rva)
    }

    private static func asciiString(_ data: Data, at offset: Int) -> String? {
        guard offset >= 0, offset < data.count else { return nil }
        var bytes: [UInt8] = []
        var cursor = offset
        while cursor < data.count, bytes.count < 512, data[cursor] >= 0x20, data[cursor] < 0x7f {
            bytes.append(data[cursor])
            cursor += 1
        }
        guard !bytes.isEmpty else { return nil }
        return String(bytes: bytes, encoding: .ascii)
    }

    private static func extractVersion(from data: Data) -> String? {
        let key = Array("FileVersion".utf8).flatMap { [$0, UInt8(0)] }
        guard let keyOffset = data.range(of: Data(key))?.upperBound else { return nil }
        var cursor = keyOffset
        while cursor + 1 < data.count {
            let value = UInt16(data[cursor]) | UInt16(data[cursor + 1]) << 8
            cursor += 2
            guard value == 0 else { continue }
            break
        }
        var scalarValues: [UInt16] = []
        while cursor + 1 < data.count, scalarValues.count < 64 {
            let value = UInt16(data[cursor]) | UInt16(data[cursor + 1]) << 8
            guard (value >= 48 && value <= 57) || value == 46 else { break }
            scalarValues.append(value)
            cursor += 2
        }
        guard scalarValues.count >= 3 else { return nil }
        let value = String(scalarValues.compactMap(UnicodeScalar.init).map(Character.init))
        return value.split(separator: ".").count >= 2 ? value : nil
    }

    private static func u16(_ data: Data, at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 1 < data.count else { return 0 }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func u32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 3 < data.count else { return 0 }
        return UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private static func intOffset(_ data: Data, at offset: Int) -> Int? {
        let value = u32(data, at: offset)
        return Int(exactly: value)
    }

    private static func checkedAdd(_ lhs: Int, _ rhs: Int) -> Int? {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? nil : value
    }

    private static func checkedMultiply(_ lhs: Int, _ rhs: Int) -> Int? {
        let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        return overflow ? nil : value
    }
}

nonisolated enum GameUpscalerAnalysisEngine {
    private struct Candidate {
        let kind: TemporalUpscalerKind
        let names: Set<String>
    }

    private static let candidates = [
        Candidate(kind: .dlss, names: ["nvngx.dll", "nvngx_dlss.dll", "nvngx_dlssg.dll"]),
        Candidate(kind: .fsr, names: [
            "amd_fidelityfx_dx12.dll", "ffx_fsr2_api_dx12_x64.dll", "ffx_fsr2_api_vk_x64.dll",
            "ffx_fsr3_x64.dll", "ffx_fsr3upscaler_x64.dll", "ffx_fsr3upscaler_x64d.dll"
        ]),
        Candidate(kind: .xess, names: ["xess.dll", "libxess.dll", "libxess_dx12.dll"])
    ]

    private static let frameGenerationNames: Set<String> = [
        "nvngx_dlssg.dll", "ffx_fsr3_x64.dll", "ffx_fsr3upscaler_x64.dll", "optifg.dll"
    ]

    private static let antiCheatMarkers: Set<String> = [
        "easyanticheat", "easyanticheat_eos", "beservice", "battleye", "vgc", "vgk",
        "ricochet", "gameguard", "xigncode", "nprotect", "eac_launcher", "bedaisy"
    ]

    static func analyze(
        gameRoot: URL,
        executable: URL? = nil,
        fileManager: FileManager = .default
    ) -> GameUpscalingCapabilities {
        let root = gameRoot.standardizedFileURL
        var files: [URL] = []
        if let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                      values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                files.append(url)
            }
        }

        let gameArchitecture = executable.map { WindowsPEInspection.inspect($0, fileManager: fileManager).architecture }
            ?? .unknown
        func capability(for candidate: Candidate) -> TemporalUpscalerCapability? {
            let matches = files.filter { candidate.names.contains($0.lastPathComponent.lowercased()) }
            guard !matches.isEmpty else { return nil }
            var evidence: [UpscalerDetectionEvidence] = []
            var acceptedURLs: [URL] = []
            var versions = Set<String>()
            var hasOnlyInvalidMatches = true
            for url in matches {
                let relative = relativePath(of: url, to: root)
                evidence.append(UpscalerDetectionEvidence(source: .fileName, path: relative, detail: "Exact library filename matched."))
                let pe = WindowsPEInspection.inspect(url, fileManager: fileManager)
                if let version = pe.version { versions.insert(version) }
                if !pe.isPE {
                    evidence.append(UpscalerDetectionEvidence(source: .peArchitecture, path: relative, detail: "The file is not a valid PE image; it is not accepted as an upscaler interface.", accepted: false))
                    continue
                }
                let architectureMatches = gameArchitecture == .unknown || pe.architecture == .unknown || pe.architecture == gameArchitecture
                evidence.append(UpscalerDetectionEvidence(
                    source: .peArchitecture,
                    path: relative,
                    detail: "PE architecture: \(pe.architecture.rawValue)\(architectureMatches ? "" : "; does not match the game executable")",
                    accepted: architectureMatches
                ))
                guard architectureMatches else { continue }
                hasOnlyInvalidMatches = false
                acceptedURLs.append(url)
                if pe.version != nil { evidence.append(UpscalerDetectionEvidence(source: .peVersionMetadata, path: relative, detail: "FileVersion metadata was read from the PE resource.")) }
                if !pe.imports.isEmpty { evidence.append(UpscalerDetectionEvidence(source: .peImports, path: relative, detail: "PE import table was read without loading the image.")) }
                if !pe.exports.isEmpty { evidence.append(UpscalerDetectionEvidence(source: .exportedSymbols, path: relative, detail: "PE export table was read without loading the image.")) }
            }
            let confidence: CapabilityConfidence = if hasOnlyInvalidMatches {
                .low
            } else if acceptedURLs.contains(where: { WindowsPEInspection.inspect($0).imports.count > 0 || WindowsPEInspection.inspect($0).exports.count > 0 }) {
                .high
            } else {
                .medium
            }
            return TemporalUpscalerCapability(
                kind: candidate.kind,
                detected: !acceptedURLs.isEmpty,
                version: versions.count == 1 ? versions.first : nil,
                confidence: confidence,
                sources: Array(Set(evidence.filter(\.accepted).map(\.source))).sorted { $0.rawValue < $1.rawValue },
                evidence: evidence,
                fileURLs: acceptedURLs.sorted { $0.path < $1.path }
            )
        }

        let capabilities = candidates.map { capability(for: $0) }
        let generationEvidence = files.filter { frameGenerationNames.contains($0.lastPathComponent.lowercased()) }.map {
            UpscalerDetectionEvidence(source: .fileName, path: relativePath(of: $0, to: root), detail: "Frame-generation library was detected; runtime operation is not proven.")
        }
        let markerEvidence = files.compactMap { url -> UpscalerDetectionEvidence? in
            let name = url.lastPathComponent.lowercased()
            guard antiCheatMarkers.contains(name) || antiCheatMarkers.contains(where: { name.hasPrefix($0 + ".") }) else { return nil }
            return UpscalerDetectionEvidence(source: .fileName, path: relativePath(of: url, to: root), detail: "Known anti-cheat marker found.")
        }
        let antiCheat = AntiCheatDetection(
            detected: !markerEvidence.isEmpty,
            markers: markerEvidence.map(\.path).sorted(),
            evidence: markerEvidence
        )
        return GameUpscalingCapabilities(
            gameRoot: root,
            analyzedAt: Date(),
            dlss: capabilities.compactMap { $0 }.first(where: { $0.kind == .dlss }),
            fsr: capabilities.compactMap { $0 }.first(where: { $0.kind == .fsr }),
            xess: capabilities.compactMap { $0 }.first(where: { $0.kind == .xess }),
            frameGeneration: FrameGenerationCapability(
                support: generationEvidence.isEmpty ? .unavailable : .candidate,
                evidence: generationEvidence
            ),
            antiCheat: antiCheat
        )
    }

    private static func relativePath(of url: URL, to root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        return filePath.hasPrefix(rootPath + "/") ? String(filePath.dropFirst(rootPath.count + 1)) : url.lastPathComponent
    }
}

actor GameUpscalerAnalyzer {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    func analyze(gameRoot: URL, executable: URL? = nil) -> GameUpscalingCapabilities {
        GameUpscalerAnalysisEngine.analyze(gameRoot: gameRoot, executable: executable, fileManager: fileManager)
    }
}

// MARK: - Runtime payload capability

nonisolated enum TemporalCapabilitySource: String, Codable, Sendable, Hashable {
    case runtimePayload
    case managedComponentStore
    case runtimeManifest
    case unavailable
}

nonisolated struct MetalFXBridgeCapabilities: Codable, Sendable, Hashable {
    let available: Bool
    let installed: Bool
    let source: TemporalCapabilitySource
    let supportsSpatial: Bool
    let supportsTemporal: Bool
    let requiredEnvironmentVariables: [String]
    let requiredDLLs: [String]
    let evidence: [UpscalerDetectionEvidence]
}

nonisolated enum MetalFXBridgeAnalyzer {
    static func inspect(runtime: InstalledRuntime, fileManager: FileManager = .default) -> MetalFXBridgeCapabilities {
        guard runtime.resolvedEngine == .gamePortingToolkit else {
            return MetalFXBridgeCapabilities(
                available: false,
                installed: false,
                source: .unavailable,
                supportsSpatial: false,
                supportsTemporal: false,
                requiredEnvironmentVariables: [],
                requiredDLLs: [],
                evidence: []
            )
        }
        let runtimeRoot = runtime.rootURL.appending(path: "Runtime/Wine.app/Contents/Resources/wine", directoryHint: .isDirectory)
        var payloadFiles: [URL] = []
        if let enumerator = fileManager.enumerator(at: runtimeRoot, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]), values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                payloadFiles.append(url)
            }
        }
        let lowercasedNames = Set(payloadFiles.map { $0.lastPathComponent.lowercased() })
        let forwarderNames: Set<String> = ["nvngx-on-metalfx.dll", "nvngx_on_metalfx.dll", "nvngx-on-metalfx.so", "nvngx_on_metalfx.so"]
        let apiNames: Set<String> = ["nvapi64.dll", "nvapi.dll"]
        let forwarders = payloadFiles.filter { forwarderNames.contains($0.lastPathComponent.lowercased()) }
        let apiFiles = payloadFiles.filter { apiNames.contains($0.lastPathComponent.lowercased()) }
        let hasWindowsPair = !forwarders.filter({ $0.pathExtension.lowercased() == "dll" }).isEmpty && !apiFiles.filter({ $0.pathExtension.lowercased() == "dll" }).isEmpty
        let hasUnixForwarder = !forwarders.filter({ $0.pathExtension.lowercased() == "so" || $0.pathExtension.lowercased() == "dylib" }).isEmpty
        let available = hasWindowsPair && (hasUnixForwarder || lowercasedNames.contains("nvngx.dll"))
        let componentStoreRoot = runtime.rootURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Components", directoryHint: .isDirectory)
        let componentStore = GraphicsComponentStore(rootURL: componentStoreRoot)
        let managedVersion = "gptk-\(runtime.id)"
        let installed = componentStore
            .upscalingReference(for: .ngxToMetalFX, version: managedVersion)
            .map { componentStore.contains($0) } == true
        let evidence = forwarders.map {
            UpscalerDetectionEvidence(source: .runtimePayload, path: $0.path, detail: "NGX→MetalFX forwarder found in the selected immutable runtime payload.")
        } + apiFiles.map {
            UpscalerDetectionEvidence(source: .runtimePayload, path: $0.path, detail: "NVIDIA NGX API support file found in the selected immutable runtime payload.")
        }
        return MetalFXBridgeCapabilities(
            available: available,
            installed: installed,
            source: available ? .runtimePayload : .unavailable,
            supportsSpatial: available,
            supportsTemporal: available,
            requiredEnvironmentVariables: available ? ["D3DM_ENABLE_METALFX"] : [],
            requiredDLLs: available ? ["nvngx-on-metalfx.dll", "nvapi64.dll"] : [],
            evidence: evidence
        )
    }
}

/// Wine Fullscreen FSR1 is spatial upscaling. It intentionally accepts only
/// runtime/renderer capability inputs and never reads game temporal DLLs.
nonisolated enum SpatialUpscalingResolver {
    static func resolve(
        runtimeFeatures: RuntimeFeatures?,
        backend: GraphicsBackend
    ) -> UpscalingCapability {
        let capabilities = runtimeFeatures?.fullscreenFSRCapabilities
            ?? FullscreenFSRCapabilities(
                available: runtimeFeatures?.fullscreenFSR == true,
                source: .payloadInspection
            )
        let support = runtimeFeatures?.graphicsCapabilities?[backend.rawValue]?.fullscreenFSRSupport
            ?? GraphicsStackCatalog.stack(for: backend)?.fullscreenFSRSupportLevel
            ?? .unsupported
        if !capabilities.available || support == .unsupported {
            return UpscalingCapability(
                id: "wine-fsr1",
                title: "Wine FSR 1",
                status: .unavailable,
                detail: "Requires compatible Vulkan graphics path"
            )
        }
        if capabilities.confidence == .verified, support == .verified {
            return UpscalingCapability(
                id: "wine-fsr1",
                title: "Wine FSR 1",
                status: .verified,
                detail: "Verified for the selected runtime and graphics path"
            )
        }
        return UpscalingCapability(
            id: "wine-fsr1",
            title: "Wine FSR 1",
            status: .candidate,
            detail: "Detected, but not verified on this macOS graphics path"
        )
    }
}

// MARK: - Requested/effective temporal path

nonisolated enum TemporalUpscalingMode: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case automatic
    case native
    case dlsstweaks
    case optiScaler
    case metalFXBridge
    case disabled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .native: "Native"
        case .dlsstweaks: "DLSSTweaks"
        case .optiScaler: "OptiScaler"
        case .metalFXBridge: "NGX → MetalFX Bridge"
        case .disabled: "Disabled"
        }
    }
}

nonisolated enum TemporalUpscalerOutput: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case native
    case dlaa
    case fsr2
    case fsr3
    case xess

    var id: String { rawValue }
}

nonisolated enum TemporalQualityPreset: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case ultraQuality
    case quality
    case balanced
    case performance

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ultraQuality: "Ultra Quality"
        case .quality: "Quality"
        case .balanced: "Balanced"
        case .performance: "Performance"
        }
    }
}

nonisolated enum FrameGenerationMode: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case disabled
    case fsr
    case xess
    case optiFG
    case dlssG

    var id: String { rawValue }
}

nonisolated struct FrameGenerationConfiguration: Codable, Sendable, Hashable {
    var mode: FrameGenerationMode = .disabled
}

nonisolated enum DLSSTweaksControl: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case forceDLAA
    case scalingRatio
    case presetOverride
    case sharpening
    case autoExposureOverride
    case debugIndicator

    var id: String { rawValue }
}

nonisolated struct DLSSTweaksCapabilities: Codable, Sendable, Hashable {
    let supportedControls: Set<DLSSTweaksControl>
    let injectionFiles: [String]

    func supports(_ control: DLSSTweaksControl) -> Bool { supportedControls.contains(control) }

    init(supportedControls: Set<DLSSTweaksControl>, injectionFiles: [String] = []) {
        self.supportedControls = supportedControls
        self.injectionFiles = injectionFiles
    }

    private enum CodingKeys: String, CodingKey {
        case supportedControls
        case controls
        case injectionFiles
    }

    init(from decoder: Decoder) throws {
        if let values = try? decoder.container(keyedBy: CodingKeys.self) {
            supportedControls = try values.decodeIfPresent(Set<DLSSTweaksControl>.self, forKey: .supportedControls)
                ?? values.decodeIfPresent(Set<DLSSTweaksControl>.self, forKey: .controls)
                ?? []
            injectionFiles = try values.decodeIfPresent([String].self, forKey: .injectionFiles) ?? []
        } else {
            let values = try decoder.singleValueContainer()
            supportedControls = try values.decode(Set<DLSSTweaksControl>.self)
            injectionFiles = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(supportedControls, forKey: .supportedControls)
        try values.encode(injectionFiles, forKey: .injectionFiles)
    }
}

nonisolated struct DLSSTweaksConfiguration: Codable, Sendable, Hashable {
    var enabled = false
    var forceDLAA = false
    var scalingRatio: Double?
    var presetOverride: String?
    var sharpening: Double?
    var autoExposureOverride = false
    var debugIndicatorEnabled = false
}

nonisolated enum ProxyDLLStrategy: Codable, Sendable, Hashable {
    case automatic
    case named(String)

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .named(let value): value
        }
    }

    private enum CodingKeys: String, CodingKey { case mode, name }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .automatic:
            try values.encode("automatic", forKey: .mode)
        case .named(let name):
            try values.encode("named", forKey: .mode)
            try values.encode(name, forKey: .name)
        }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .mode) {
        case "automatic": self = .automatic
        case "named": self = .named(try values.decode(String.self, forKey: .name))
        default: throw DecodingError.dataCorruptedError(forKey: .mode, in: values, debugDescription: "Unknown proxy DLL strategy")
        }
    }
}

nonisolated struct OptiScalerConfiguration: Codable, Sendable, Hashable {
    var enabled = false
    var inputAPI: GraphicsAPI?
    var outputUpscaler: TemporalUpscalerOutput?
    var frameGeneration = FrameGenerationConfiguration()
    var proxyStrategy: ProxyDLLStrategy = .automatic
}

nonisolated struct TemporalUpscalingConfiguration: Codable, Sendable, Hashable {
    var mode: TemporalUpscalingMode = .automatic
    var quality: TemporalQualityPreset = .quality
    var outputUpscaler: TemporalUpscalerOutput?
    var frameGeneration = FrameGenerationConfiguration()
    var dlsstweaks = DLSSTweaksConfiguration()
    var optiScaler = OptiScalerConfiguration()

    static let `default` = TemporalUpscalingConfiguration()
}

nonisolated enum TemporalEffectivePath: String, Codable, Sendable, Hashable {
    case none
    case native
    case dlsstweaks
    case optiScaler
    case metalFXBridge
    case unavailable

    var displayName: String {
        switch self {
        case .none: "Not configured"
        case .native: "Native temporal upscaler"
        case .dlsstweaks: "DLSS + DLSSTweaks"
        case .optiScaler: "OptiScaler"
        case .metalFXBridge: "NGX → MetalFX"
        case .unavailable: "Unavailable"
        }
    }
}

nonisolated struct CompatibilityEvidence: Codable, Sendable, Hashable {
    let summary: String
    let details: [String]
}

nonisolated enum TemporalBridgeCompatibility: Codable, Sendable, Hashable {
    case unsupported(reason: String)
    case candidate(reason: String)
    case experimental(reason: String)
    case verified(CompatibilityEvidence)

    var label: String {
        switch self {
        case .unsupported: "Unsupported"
        case .candidate: "Candidate"
        case .experimental: "Experimental"
        case .verified: "Verified"
        }
    }

    var reason: String {
        switch self {
        case .unsupported(let reason), .candidate(let reason), .experimental(let reason): reason
        case .verified(let evidence): evidence.summary
        }
    }

    private enum CodingKeys: String, CodingKey { case state, reason, evidence }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .unsupported(let reason):
            try values.encode("unsupported", forKey: .state); try values.encode(reason, forKey: .reason)
        case .candidate(let reason):
            try values.encode("candidate", forKey: .state); try values.encode(reason, forKey: .reason)
        case .experimental(let reason):
            try values.encode("experimental", forKey: .state); try values.encode(reason, forKey: .reason)
        case .verified(let evidence):
            try values.encode("verified", forKey: .state); try values.encode(evidence, forKey: .evidence)
        }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .state) {
        case "unsupported": self = .unsupported(reason: try values.decode(String.self, forKey: .reason))
        case "candidate": self = .candidate(reason: try values.decode(String.self, forKey: .reason))
        case "experimental": self = .experimental(reason: try values.decode(String.self, forKey: .reason))
        case "verified": self = .verified(try values.decode(CompatibilityEvidence.self, forKey: .evidence))
        default: throw DecodingError.dataCorruptedError(forKey: .state, in: values, debugDescription: "Unknown temporal compatibility state")
        }
    }
}

nonisolated enum DLLInjectionSafety: String, Codable, Sendable, Hashable {
    case allowed
    case blockedAntiCheat
    case requiresConfirmation
}

nonisolated struct TemporalUpscalingPlan: Codable, Sendable, Hashable {
    let requested: TemporalUpscalingConfiguration
    let available: Bool
    let compatibility: TemporalBridgeCompatibility
    let effective: TemporalEffectivePath
    let reason: String
    let injectionSafety: DLLInjectionSafety
    let proxyStrategy: ProxyDLLStrategy
    let componentVersions: [String: String]

    var isActive: Bool { effective != .none && effective != .unavailable }

    var fingerprintSegment: String {
        let components = componentVersions.keys.sorted().map { "\($0)=\(componentVersions[$0] ?? "")" }.joined(separator: ",")
        let dlsstweaks = requested.dlsstweaks
        let optiScaler = requested.optiScaler
        let fingerprintSegments: [String] = [
            "requested=\(requested.mode.rawValue)",
            "effective=\(effective.rawValue)",
            "components=\(components)",
            "output=\(requested.outputUpscaler?.rawValue ?? "native")",
            "quality=\(requested.quality.rawValue)",
            "fg=\(requested.frameGeneration.mode.rawValue)",
            "proxy=\(proxyStrategy.displayName)",
            "dlsstweaks.enabled=\(dlsstweaks.enabled)",
            "dlsstweaks.dlaa=\(dlsstweaks.forceDLAA)",
            "dlsstweaks.ratio=\(dlsstweaks.scalingRatio.map { String($0) } ?? "default")",
            "dlsstweaks.preset=\(dlsstweaks.presetOverride ?? "default")",
            "dlsstweaks.sharpening=\(dlsstweaks.sharpening.map { String($0) } ?? "default")",
            "dlsstweaks.autoExposure=\(dlsstweaks.autoExposureOverride)",
            "dlsstweaks.debugIndicator=\(dlsstweaks.debugIndicatorEnabled)",
            "optiscaler.enabled=\(optiScaler.enabled)",
            "optiscaler.input=\(optiScaler.inputAPI?.rawValue ?? "automatic")",
            "optiscaler.output=\(optiScaler.outputUpscaler?.rawValue ?? "native")",
            "optiscaler.fg=\(optiScaler.frameGeneration.mode.rawValue)",
            "optiscaler.proxy=\(optiScaler.proxyStrategy.displayName)"
        ]
        return fingerprintSegments.joined(separator: ";")
    }
}

nonisolated struct GameLaunchContext: Sendable, Hashable {
    let applicationID: UUID
    let executable: URL
    let gameRoot: URL
    let environmentID: UUID
}

nonisolated protocol TemporalUpscalerBridge: Sendable {
    var identifier: String { get }

    func compatibility(
        game: GameUpscalingCapabilities,
        runtime: InstalledRuntime,
        graphicsStack: GraphicsStack
    ) async -> TemporalBridgeCompatibility

    func preparePlan(
        configuration: TemporalUpscalingConfiguration,
        context: GameLaunchContext
    ) async throws -> TemporalUpscalingPlan
}

nonisolated struct TemporalComponentReference: Codable, Sendable, Hashable, Identifiable {
    let componentID: String
    let version: String
    let source: TemporalComponentSource
    let sha256: String
    let installedAt: Date
    let supportedArchitectures: Set<WindowsExecutableArchitecture>
    let requiredFiles: [String]
    let licenseMetadata: String?

    var id: String { "\(componentID):\(version)" }
}

/// A provider supplies metadata and a validated component directory. Network
/// code is intentionally outside the domain model so a catalog, user import,
/// or an external source cannot silently become a hard-coded download path.
nonisolated struct DLSSRuntimeCandidate: Codable, Sendable, Hashable, Identifiable {
    let version: String
    let source: TemporalComponentSource
    /// The SHA-256 of the component directory, using the same deterministic
    /// file-list digest as ManagedTemporalComponentStore and excluding its
    /// generated component.json receipt.
    let expectedSHA256: String?
    let expectedSize: Int64?
    let sourceHost: String?
    let licenseMetadata: String?

    var id: String { version }
}

nonisolated protocol DLSSRuntimeProviding: Sendable {
    var identifier: String { get }

    func candidates() async throws -> [DLSSRuntimeCandidate]
    func componentDirectory(for candidate: DLSSRuntimeCandidate) async throws -> URL
}

/// The component author must explicitly declare which files are safe to
/// install next to a game's executable. This prevents a generic archive
/// importer from copying every DLL, debug binary, or unrelated file into a
/// game directory.
nonisolated struct TemporalComponentInjectionManifest: Codable, Sendable, Hashable {
    let files: [String]
    let proxyStrategy: ProxyDLLStrategy?
}

/// OptiScaler's release archive does not contain Boreal's internal
/// `injection.json`. Its package layout is nevertheless well-defined: the
/// compiled hook is named OptiScaler.dll, the configuration is OptiScaler.ini,
/// and runtime payloads live in the OptiScaler/ directory. Build a manifest
/// only from that narrow, known layout instead of treating every DLL in an
/// arbitrary source tree as injectable.
nonisolated enum OptiScalerComponentManifestFactory {
    private static let mainDLLNames: Set<String> = ["optiscaler.dll", "nvngx.dll"]
    private static let supportedExtensions: Set<String> = [
        "dll", "dylib", "so", "ini", "asi", "bin", "cso", "dat", "hlsl", "json", "spv", "ttf"
    ]

    static func installableFiles(from files: [String]) -> [String] {
        let safeFiles = files.filter(TemporalComponentSecurity.isSafeRelativePath)
        guard safeFiles.contains(where: { path in
            mainDLLNames.contains(URL(fileURLWithPath: path).lastPathComponent.lowercased())
        }) else { return [] }
        return safeFiles.filter { path in
            guard URL(fileURLWithPath: path).lastPathComponent.lowercased() != "injection.json" else { return false }
            let components = path.split(separator: "/")
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { return false }
            let isRootFile = components.count == 1
            let isOptiPayload = components.first.map { String($0).lowercased() } == "optiscaler"
            return isRootFile || isOptiPayload
        }.sorted(by: pathOrder)
    }

    static func make(from requiredFiles: [String]) -> TemporalComponentInjectionManifest? {
        let files = installableFiles(from: requiredFiles)
        guard let main = files
            .filter({ mainDLLNames.contains(URL(fileURLWithPath: $0).lastPathComponent.lowercased()) })
            .sorted(by: pathOrder)
            .first else {
            return nil
        }
        guard files.contains(main) else { return nil }

        let proxyStrategy: ProxyDLLStrategy = URL(fileURLWithPath: main).lastPathComponent.lowercased() == "optiscaler.dll"
            ? .named("dxgi.dll")
            : .automatic
        return TemporalComponentInjectionManifest(files: files, proxyStrategy: proxyStrategy)
    }

    private static func pathOrder(_ lhs: String, _ rhs: String) -> Bool {
        let lhsDepth = lhs.split(separator: "/").count
        let rhsDepth = rhs.split(separator: "/").count
        return lhsDepth == rhsDepth ? lhs < rhs : lhsDepth < rhsDepth
    }
}

nonisolated enum TemporalComponentSource: String, Codable, CaseIterable, Sendable, Hashable {
    case curatedCatalog
    case userImport
    case runtimePayload
    case externalProvider
}

nonisolated enum TemporalComponentID: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case dlsstweaks = "DLSSTweaks"
    case optiScaler = "OptiScaler"
    case dlssRuntime = "DLSSRuntime"

    var id: String { rawValue }

    var displayName: String { rawValue }
}

nonisolated struct ExternalDLLInjectionStatus: Codable, Sendable, Hashable {
    let safety: DLLInjectionSafety
    let detail: String
}

nonisolated enum TemporalUpscalingResolutionEngine {
    static func resolve(
        game: GameUpscalingCapabilities,
        runtime: InstalledRuntime,
        graphicsStack: GraphicsStack,
        configuration: TemporalUpscalingConfiguration,
        metalFX: MetalFXBridgeCapabilities,
        dlsstweaks: TemporalComponentReference?,
        optiScaler: TemporalComponentReference?,
        applicationID: UUID = UUID()
    ) -> TemporalUpscalingPlan {
        let injectionSafety: DLLInjectionSafety = if game.antiCheat.detected {
            .blockedAntiCheat
        } else {
            // No automatic DLL injection is permitted until a game profile or
            // explicit user action establishes that it is acceptable.
            .requiresConfirmation
        }
        let safetyDetail: String = switch injectionSafety {
        case .blockedAntiCheat: "External DLL injection is disabled because anti-cheat or integrity protection markers were detected."
        case .requiresConfirmation: "External DLL injection requires an explicit user action because this game's policy is unknown."
        case .allowed: "External DLL injection is allowed by a verified game policy."
        }
        func nativePlan() -> TemporalUpscalingPlan {
            guard let interface = game.detectedTemporalInterfaces.first else {
                return TemporalUpscalingPlan(
                    requested: configuration,
                    available: false,
                    compatibility: .unsupported(reason: "No native DLSS, FSR 2+ or XeSS interface was detected in the game files."),
                    effective: .unavailable,
                    reason: "No native temporal interface is available.",
                    injectionSafety: injectionSafety,
                    proxyStrategy: .automatic,
                    componentVersions: [:]
                )
            }
            return TemporalUpscalingPlan(
                requested: configuration,
                available: true,
                compatibility: .candidate(reason: "\(interface.kind.displayName) was detected, but a running game smoke test has not verified the native path."),
                effective: .native,
                reason: "Native temporal interface detected; operation remains unverified.",
                injectionSafety: injectionSafety,
                proxyStrategy: .automatic,
                componentVersions: interface.version.map { [interface.kind.rawValue: $0] } ?? [:]
            )
        }

        func bridgePlan(_ mode: TemporalUpscalingMode) -> TemporalUpscalingPlan {
            switch mode {
            case .metalFXBridge:
                guard graphicsStack.backend == .d3dMetal else {
                    return unavailable("NGX → MetalFX requires the D3DMetal graphics stack.")
                }
                guard metalFX.available else {
                    return unavailable("The selected immutable GPTK runtime does not contain a detected NGX → MetalFX payload.")
                }
                guard metalFX.installed else {
                    return unavailable("The NGX → MetalFX payload is available in the selected runtime but has not been installed into Boreal's managed ComponentStore.")
                }
                guard game.dlss?.detected == true else {
                    return unavailable("The game does not expose a detected DLSS/NGX interface for this bridge.")
                }
                return TemporalUpscalingPlan(
                    requested: configuration,
                    available: true,
                    compatibility: .experimental(reason: "The runtime payload is present, but NGX → MetalFX has not been live verified for this game on macOS."),
                    effective: .metalFXBridge,
                    reason: "The bridge is available from the selected runtime; live compatibility is experimental.",
                    injectionSafety: injectionSafety,
                    proxyStrategy: .automatic,
                    componentVersions: ["metalfx-bridge": "runtime-payload"]
                )
            case .dlsstweaks:
                guard configuration.dlsstweaks.enabled else {
                    return unavailable("DLSSTweaks is installed but is not enabled for this game. Perform the explicit per-game injection first.")
                }
                guard game.dlss?.detected == true else { return unavailable("DLSSTweaks requires a detected native DLSS interface.") }
                guard let dlsstweaks else { return unavailable("DLSSTweaks is not installed in Boreal's managed ComponentStore.") }
                guard injectionSafety != .blockedAntiCheat else { return unavailable(safetyDetail) }
                return TemporalUpscalingPlan(
                    requested: configuration,
                    available: true,
                    compatibility: .experimental(reason: "DLSSTweaks is managed, but its game injection path has not been live verified for this configuration."),
                    effective: .dlsstweaks,
                    reason: "DLSSTweaks is available after explicit installation; launch injection still requires user confirmation.",
                    injectionSafety: injectionSafety,
                    proxyStrategy: .automatic,
                    componentVersions: ["dlsstweaks": dlsstweaks.version]
                )
            case .optiScaler:
                guard configuration.optiScaler.enabled else {
                    return unavailable("OptiScaler is installed but is not enabled for this game. Perform the explicit per-game injection first.")
                }
                guard game.hasTemporalInterface else { return unavailable("OptiScaler requires a detected DLSS, FSR 2+ or XeSS interface.") }
                guard let optiScaler else { return unavailable("OptiScaler is not installed in Boreal's managed ComponentStore.") }
                guard [.d3dMetal, .dxmt, .dxvk, .vkd3d].contains(graphicsStack.backend) else {
                    return unavailable("OptiScaler requires a Direct3D translation stack with a detected temporal interface.")
                }
                guard injectionSafety != .blockedAntiCheat else { return unavailable(safetyDetail) }
                return TemporalUpscalingPlan(
                    requested: configuration,
                    available: true,
                    compatibility: .experimental(reason: "OptiScaler has not been live verified for this game, renderer and macOS runtime."),
                    effective: .optiScaler,
                    reason: "OptiScaler is available after explicit installation; launch injection still requires user confirmation.",
                    injectionSafety: injectionSafety,
                    proxyStrategy: configuration.optiScaler.proxyStrategy,
                    componentVersions: ["optiscaler": optiScaler.version]
                )
            case .native, .automatic:
                return nativePlan()
            case .disabled:
                return TemporalUpscalingPlan(
                    requested: configuration,
                    available: true,
                    compatibility: .candidate(reason: "Temporal upscaling is disabled by the requested configuration."),
                    effective: .none,
                    reason: "No temporal bridge or replacement is requested.",
                    injectionSafety: injectionSafety,
                    proxyStrategy: .automatic,
                    componentVersions: [:]
                )
            }
        }

        if configuration.mode == .automatic {
            // Native stays first, but only as a candidate. The resolver never
            // upgrades candidate compatibility to verified.
            let native = nativePlan()
            if native.available { return native }
            if metalFX.available, metalFX.installed, game.dlss?.detected == true, graphicsStack.backend == .d3dMetal {
                return bridgePlan(.metalFXBridge)
            }
            if configuration.dlsstweaks.enabled, dlsstweaks != nil, game.dlss?.detected == true {
                return bridgePlan(.dlsstweaks)
            }
            if configuration.optiScaler.enabled, optiScaler != nil, game.hasTemporalInterface {
                return bridgePlan(.optiScaler)
            }
            return native
        }
        return bridgePlan(configuration.mode)

        func unavailable(_ reason: String) -> TemporalUpscalingPlan {
            TemporalUpscalingPlan(
                requested: configuration,
                available: false,
                compatibility: .unsupported(reason: reason),
                effective: .unavailable,
                reason: reason,
                injectionSafety: injectionSafety,
                proxyStrategy: configuration.optiScaler.proxyStrategy,
                componentVersions: [:]
            )
        }
    }
}

actor TemporalUpscalingResolver {
    func resolve(
        game: GameUpscalingCapabilities,
        runtime: InstalledRuntime,
        graphicsStack: GraphicsStack,
        configuration: TemporalUpscalingConfiguration,
        metalFX: MetalFXBridgeCapabilities,
        dlsstweaks: TemporalComponentReference?,
        optiScaler: TemporalComponentReference?,
        applicationID: UUID
    ) -> TemporalUpscalingPlan {
        TemporalUpscalingResolutionEngine.resolve(
            game: game,
            runtime: runtime,
            graphicsStack: graphicsStack,
            configuration: configuration,
            metalFX: metalFX,
            dlsstweaks: dlsstweaks,
            optiScaler: optiScaler,
            applicationID: applicationID
        )
    }
}

// MARK: - Managed temporal components

nonisolated enum TemporalComponentError: LocalizedError, Sendable {
    case unsafeVersion(String)
    case unsafePath(String)
    case sourceUnavailable(URL)
    case invalidComponent(String)
    case checksumMismatch(expected: String, actual: String)
    case componentAlreadyInstalled(String)

    var errorDescription: String? {
        switch self {
        case .unsafeVersion(let version): "The component version is unsafe: \(version)"
        case .unsafePath(let path): "The component contains an unsafe path: \(path)"
        case .sourceUnavailable(let url): "The component source is unavailable: \(url.path)"
        case .invalidComponent(let detail): "The component is invalid: \(detail)"
        case .checksumMismatch: "The component checksum does not match its managed receipt."
        case .componentAlreadyInstalled(let id): "The managed component is already installed: \(id)"
        }
    }
}

nonisolated enum TemporalComponentSecurity {
    static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty
            && !path.hasPrefix("/")
            && !path.contains("\\")
            && !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
    }

    static func directorySHA256(
        _ root: URL,
        excluding excludedNames: Set<String> = [],
        fileManager: FileManager = .default
    ) throws -> String {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { throw TemporalComponentError.invalidComponent("The component directory cannot be enumerated.") }
        var files: [(relative: String, url: URL)] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let relative = relativePath(of: url, to: root)
            guard Self.isSafeRelativePath(relative) else { throw TemporalComponentError.unsafePath(relative) }
            guard !excludedNames.contains(url.lastPathComponent) else { continue }
            files.append((relative, url))
        }
        files.sort { $0.relative < $1.relative }
        var hasher = SHA256()
        for file in files {
            hasher.update(data: Data(file.relative.utf8))
            hasher.update(data: Data([0]))
            let handle = try FileHandle(forReadingFrom: file.url)
            defer { try? handle.close() }
            while true {
                let data = try handle.read(upToCount: 4 * 1_024 * 1_024) ?? Data()
                if data.isEmpty { break }
                hasher.update(data: data)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func directoryByteSize(
        _ root: URL,
        excluding excludedNames: Set<String> = [],
        fileManager: FileManager = .default
    ) throws -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { throw TemporalComponentError.invalidComponent("The component directory cannot be enumerated.") }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            guard !excludedNames.contains(url.lastPathComponent) else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    static func relativePath(of url: URL, to root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        return filePath.hasPrefix(rootPath + "/") ? String(filePath.dropFirst(rootPath.count + 1)) : url.lastPathComponent
    }

    static func isSafeExistingDirectory(_ url: URL, fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return true }
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    static func isSafeVersion(_ version: String) -> Bool {
        !version.isEmpty && version != "." && version != ".." && !version.contains("/") && !version.contains("\\") && !version.contains("..")
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

nonisolated struct ManagedTemporalComponentStore: @unchecked Sendable {
    let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
    }

    init(applicationSupportURL: URL, fileManager: FileManager = .default) {
        self.init(rootURL: applicationSupportURL.appending(path: "Components", directoryHint: .isDirectory), fileManager: fileManager)
    }

    func componentURL(_ id: TemporalComponentID, version: String) -> URL {
        rootURL.appending(path: "Upscaling", directoryHint: .isDirectory)
            .appending(path: id.rawValue, directoryHint: .isDirectory)
            .appending(path: version, directoryHint: .isDirectory)
    }

    func reference(for id: TemporalComponentID, version: String? = nil) -> TemporalComponentReference? {
        references(for: id).first {
            (version == nil || $0.version == version) && contains($0)
        }
    }

    func references(for id: TemporalComponentID) -> [TemporalComponentReference] {
        let base = rootURL.appending(path: "Upscaling", directoryHint: .isDirectory).appending(path: id.rawValue, directoryHint: .isDirectory)
        guard let children = try? fileManager.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        return children.compactMap { directory in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let receipt = directory.appending(path: "component.json")
            guard let data = try? Data(contentsOf: receipt),
                  let reference = try? TemporalComponentSecurity.makeDecoder().decode(TemporalComponentReference.self, from: data),
                  reference.componentID == id.rawValue,
                  reference.version == directory.lastPathComponent,
                  TemporalComponentSecurity.isSafeVersion(reference.version),
                  reference.sha256.count == 64,
                  reference.sha256.allSatisfy(\.isHexDigit),
                  reference.requiredFiles.allSatisfy(TemporalComponentSecurity.isSafeRelativePath) else { return nil }
            return reference
        }.sorted { $0.version.localizedStandardCompare($1.version) == .orderedDescending }
    }

    func contains(_ reference: TemporalComponentReference) -> Bool {
        guard TemporalComponentSecurity.isSafeVersion(reference.version) else { return false }
        let directory = componentURL(.init(rawValue: reference.componentID) ?? .optiScaler, version: reference.version)
        guard fileManager.fileExists(atPath: directory.path),
              let data = try? Data(contentsOf: directory.appending(path: "component.json")),
              let stored = try? TemporalComponentSecurity.makeDecoder().decode(TemporalComponentReference.self, from: data),
              stored.componentID == reference.componentID,
              stored.version == reference.version,
              stored.source == reference.source,
              stored.sha256.caseInsensitiveCompare(reference.sha256) == .orderedSame,
              stored.supportedArchitectures == reference.supportedArchitectures,
              stored.requiredFiles == reference.requiredFiles,
              stored.licenseMetadata == reference.licenseMetadata else { return false }
        guard let digest = try? TemporalComponentSecurity.directorySHA256(directory, excluding: ["component.json"], fileManager: fileManager), digest == reference.sha256 else { return false }
        return !reference.requiredFiles.isEmpty && reference.requiredFiles.allSatisfy { fileManager.isReadableFile(atPath: directory.appending(path: $0).path) }
    }

    func install(
        id: TemporalComponentID,
        version: String,
        source: URL,
        sourceKind: TemporalComponentSource,
        licenseMetadata: String? = nil
    ) throws -> TemporalComponentReference {
        guard TemporalComponentSecurity.isSafeVersion(version) else { throw TemporalComponentError.unsafeVersion(version) }
        let source = source.standardizedFileURL
        var sourceIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &sourceIsDirectory), sourceIsDirectory.boolValue,
              TemporalComponentSecurity.isSafeExistingDirectory(source, fileManager: fileManager) else {
            throw TemporalComponentError.sourceUnavailable(source)
        }
        let destination = componentURL(id, version: version)
        if let existing = reference(for: id, version: version) {
            if contains(existing) { throw TemporalComponentError.componentAlreadyInstalled(existing.id) }
            throw TemporalComponentError.invalidComponent("An incomplete managed component exists at \(destination.path).")
        }
        if fileManager.fileExists(atPath: destination.path) {
            throw TemporalComponentError.invalidComponent("An incomplete managed component exists at \(destination.path).")
        }

        let staging = rootURL.appending(path: ".installing/\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        var files: [String] = []
        guard let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            throw TemporalComponentError.invalidComponent("The component directory cannot be enumerated.")
        }
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true else {
                if values.isSymbolicLink == true { throw TemporalComponentError.unsafePath(item.lastPathComponent) }
                continue
            }
            guard values.isSymbolicLink != true else { throw TemporalComponentError.unsafePath(item.lastPathComponent) }
            guard item.lastPathComponent != "component.json" else { continue }
            let relative = TemporalComponentSecurity.relativePath(of: item, to: source)
            guard TemporalComponentSecurity.isSafeRelativePath(relative) else { throw TemporalComponentError.unsafePath(relative) }
            let target = staging.appending(path: relative)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: item, to: target)
            files.append(relative)
        }
        files.sort()
        guard !files.isEmpty else { throw TemporalComponentError.invalidComponent("The component directory is empty.") }
        let supportedFiles = files.filter { path in
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            return ext == "dll" || ext == "dylib" || ext == "so" || ext == "ini"
        }
        let requiredFiles: [String]
        if id == .optiScaler {
            requiredFiles = OptiScalerComponentManifestFactory.installableFiles(from: files)
        } else {
            requiredFiles = supportedFiles
        }
        guard !requiredFiles.isEmpty else { throw TemporalComponentError.invalidComponent("The component contains no supported runtime/configuration files.") }
        if id == .optiScaler, OptiScalerComponentManifestFactory.make(from: requiredFiles) == nil {
            throw TemporalComponentError.invalidComponent(
                "The selected OptiScaler folder does not contain a compiled OptiScaler.dll or legacy nvngx.dll. Choose a release/build artifact, not the project source folder."
            )
        }
        let dllFiles = files.filter { URL(fileURLWithPath: $0).pathExtension.lowercased() == "dll" }
        guard !dllFiles.isEmpty else {
            throw TemporalComponentError.invalidComponent("The component contains no Windows DLL.")
        }
        var architectures = Set<WindowsExecutableArchitecture>()
        for path in dllFiles {
            let inspection = WindowsPEInspection.inspect(staging.appending(path: path))
            guard inspection.isPE, inspection.architecture != .unknown else {
                throw TemporalComponentError.invalidComponent("The DLL is not a valid x86 or x86_64 PE image: \(path)")
            }
            architectures.insert(inspection.architecture)
        }
        let digest = try TemporalComponentSecurity.directorySHA256(staging, fileManager: fileManager)
        let reference = TemporalComponentReference(
            componentID: id.rawValue,
            version: version,
            source: sourceKind,
            sha256: digest,
            installedAt: Date(),
            supportedArchitectures: architectures,
            requiredFiles: requiredFiles,
            licenseMetadata: licenseMetadata
        )
        try TemporalComponentSecurity.makeEncoder().encode(reference).write(to: staging.appending(path: "component.json"), options: .atomic)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: staging, to: destination)
        do {
            try makeImmutable(destination)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        return reference
    }

    private func makeImmutable(_ root: URL) throws {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isExecutableKey],
            options: []
        ) else { return }
        var urls = [root]
        for case let url as URL in enumerator { urls.append(url) }
        for url in urls.reversed() {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isExecutableKey])
            guard values.isSymbolicLink != true else { continue }
            let permissions: Int = values.isDirectory == true || values.isExecutable == true ? 0o555 : 0o444
            try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }
}

actor DLSSTweaksManager {
    private let store: ManagedTemporalComponentStore

    init(store: ManagedTemporalComponentStore) { self.store = store }

    func installedReference(version: String? = nil) -> TemporalComponentReference? {
        store.reference(for: .dlsstweaks, version: version)
    }

    func install(from source: URL, version: String, licenseMetadata: String? = nil) throws -> TemporalComponentReference {
        try store.install(id: .dlsstweaks, version: version, source: source, sourceKind: .userImport, licenseMetadata: licenseMetadata)
    }

    func validate(_ reference: TemporalComponentReference) -> Bool { store.contains(reference) }

    func capabilities(for reference: TemporalComponentReference) -> DLSSTweaksCapabilities {
        // Controls are advertised only when a component ships a declarative
        // capabilities.json. This prevents a UI toggle from implying support
        // that a particular DLSSTweaks release does not contain.
        let root = store.componentURL(.dlsstweaks, version: reference.version)
        let url = root.appending(path: "capabilities.json")
        guard let data = try? Data(contentsOf: url),
              let values = try? TemporalComponentSecurity.makeDecoder().decode(DLSSTweaksCapabilities.self, from: data) else {
            return DLSSTweaksCapabilities(supportedControls: [])
        }
        return values
    }

    func inject(
        reference: TemporalComponentReference,
        gameRoot: URL,
        applicationID: UUID,
        targetArchitecture: WindowsExecutableArchitecture = .unknown,
        antiCheat: AntiCheatDetection = .unknown,
        confirmUnknownInjectionPolicy: Bool = false
    ) throws -> ManagedInjectionReceipt {
        guard store.contains(reference) else { throw TemporalInjectionError.componentUnavailable(reference.id) }
        if antiCheat.detected { throw TemporalInjectionError.antiCheatDetected }
        if !confirmUnknownInjectionPolicy { throw TemporalInjectionError.confirmationRequired }
        let manifest = try injectionManifest(for: reference)
        return try TemporalComponentInjection.inject(
            componentRoot: store.componentURL(.dlsstweaks, version: reference.version),
            reference: reference,
            relativeFiles: manifest.files,
            gameRoot: gameRoot,
            applicationID: applicationID,
            bridgeID: "dlsstweaks",
            targetArchitecture: targetArchitecture,
            antiCheat: antiCheat,
            confirmUnknownInjectionPolicy: confirmUnknownInjectionPolicy,
            proxyStrategy: manifest.proxyStrategy ?? .automatic,
            configurationFingerprint: "component=\(reference.id)"
        )
    }

    func restore(_ receipt: ManagedInjectionReceipt, gameRoot: URL) throws {
        try TemporalComponentInjection.restore(receipt, gameRoot: gameRoot)
    }

    private func injectionManifest(for reference: TemporalComponentReference) throws -> TemporalComponentInjectionManifest {
        let url = store.componentURL(.dlsstweaks, version: reference.version).appending(path: "injection.json")
        guard let data = try? Data(contentsOf: url),
              let manifest = try? TemporalComponentSecurity.makeDecoder().decode(TemporalComponentInjectionManifest.self, from: data),
              !manifest.files.isEmpty,
              manifest.files.allSatisfy({ TemporalComponentSecurity.isSafeRelativePath($0) && reference.requiredFiles.contains($0) }) else {
            throw TemporalInjectionError.componentUnavailable("DLSSTweaks injection.json is missing or does not declare a safe subset of required files.")
        }
        return manifest
    }
}

actor OptiScalerManager {
    private let store: ManagedTemporalComponentStore

    init(store: ManagedTemporalComponentStore) { self.store = store }

    func installedReference(version: String? = nil) -> TemporalComponentReference? {
        store.references(for: .optiScaler).first {
            (version == nil || $0.version == version)
                && OptiScalerComponentManifestFactory.make(from: $0.requiredFiles) != nil
                && store.contains($0)
        }
    }

    func install(from source: URL, version: String, licenseMetadata: String? = nil) throws -> TemporalComponentReference {
        let resolvedVersion: String
        if let existing = store.references(for: .optiScaler).first(where: { $0.version == version }) {
            let suffix = OptiScalerComponentManifestFactory.make(from: existing.requiredFiles) == nil
                ? "repaired"
                : "reimport"
            resolvedVersion = "\(version)-\(suffix)-\(UUID().uuidString.prefix(8))"
        } else {
            resolvedVersion = version
        }
        return try store.install(
            id: .optiScaler,
            version: resolvedVersion,
            source: source,
            sourceKind: .userImport,
            licenseMetadata: licenseMetadata
        )
    }

    func validate(_ reference: TemporalComponentReference) -> Bool { store.contains(reference) }

    func inject(
        reference: TemporalComponentReference,
        configuration: OptiScalerConfiguration,
        gameRoot: URL,
        applicationID: UUID,
        targetArchitecture: WindowsExecutableArchitecture = .unknown,
        antiCheat: AntiCheatDetection = .unknown,
        confirmUnknownInjectionPolicy: Bool = false
    ) throws -> ManagedInjectionReceipt {
        guard store.contains(reference) else { throw TemporalInjectionError.componentUnavailable(reference.id) }
        guard configuration.enabled else {
            throw TemporalInjectionError.componentUnavailable("OptiScaler is disabled in the requested configuration.")
        }
        if antiCheat.detected { throw TemporalInjectionError.antiCheatDetected }
        if !confirmUnknownInjectionPolicy { throw TemporalInjectionError.confirmationRequired }
        let manifest = try injectionManifest(for: reference)
        return try TemporalComponentInjection.inject(
            componentRoot: store.componentURL(.optiScaler, version: reference.version),
            reference: reference,
            relativeFiles: manifest.files,
            gameRoot: gameRoot,
            applicationID: applicationID,
            bridgeID: "optiscaler",
            targetArchitecture: targetArchitecture,
            antiCheat: antiCheat,
            confirmUnknownInjectionPolicy: confirmUnknownInjectionPolicy,
            proxyStrategy: configuration.proxyStrategy == .automatic
                ? manifest.proxyStrategy ?? .automatic
                : configuration.proxyStrategy,
            configurationFingerprint: makeConfigurationFingerprint(configuration)
        )
    }

    func restore(_ receipt: ManagedInjectionReceipt, gameRoot: URL) throws {
        try TemporalComponentInjection.restore(receipt, gameRoot: gameRoot)
    }

    private func makeConfigurationFingerprint(_ configuration: OptiScalerConfiguration) -> String {
        [
            "enabled=\(configuration.enabled)",
            "input=\(configuration.inputAPI?.rawValue ?? "automatic")",
            "output=\(configuration.outputUpscaler?.rawValue ?? "native")",
            "fg=\(configuration.frameGeneration.mode.rawValue)",
            "proxy=\(configuration.proxyStrategy.displayName)"
        ].joined(separator: "|")
    }

    private func injectionManifest(for reference: TemporalComponentReference) throws -> TemporalComponentInjectionManifest {
        let url = store.componentURL(.optiScaler, version: reference.version).appending(path: "injection.json")
        if let data = try? Data(contentsOf: url),
           let manifest = try? TemporalComponentSecurity.makeDecoder().decode(TemporalComponentInjectionManifest.self, from: data),
           !manifest.files.isEmpty,
           manifest.files.allSatisfy({ TemporalComponentSecurity.isSafeRelativePath($0) && reference.requiredFiles.contains($0) }) {
            return manifest
        }
        if let manifest = OptiScalerComponentManifestFactory.make(from: reference.requiredFiles) {
            return manifest
        }
        throw TemporalInjectionError.componentUnavailable(
            "The managed component does not contain a compiled OptiScaler.dll, legacy nvngx.dll, or a valid injection manifest."
        )
    }
}

nonisolated struct ManagedInjectionReceipt: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let applicationID: UUID
    let bridgeID: String
    let componentVersion: String
    let createdFiles: [String]
    let createdDirectories: [String]
    let replacedFiles: [ReplacedFileReceipt]
    let configurationFingerprint: String
    let createdAt: Date
    let gameRootPath: String

    private enum CodingKeys: String, CodingKey {
        case id, applicationID, bridgeID, componentVersion, createdFiles, createdDirectories
        case replacedFiles, configurationFingerprint, createdAt, gameRootPath
    }

    init(
        id: UUID,
        applicationID: UUID,
        bridgeID: String,
        componentVersion: String,
        createdFiles: [String],
        createdDirectories: [String] = [],
        replacedFiles: [ReplacedFileReceipt],
        configurationFingerprint: String,
        createdAt: Date,
        gameRootPath: String
    ) {
        self.id = id
        self.applicationID = applicationID
        self.bridgeID = bridgeID
        self.componentVersion = componentVersion
        self.createdFiles = createdFiles
        self.createdDirectories = createdDirectories
        self.replacedFiles = replacedFiles
        self.configurationFingerprint = configurationFingerprint
        self.createdAt = createdAt
        self.gameRootPath = gameRootPath
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        applicationID = try values.decode(UUID.self, forKey: .applicationID)
        bridgeID = try values.decode(String.self, forKey: .bridgeID)
        componentVersion = try values.decode(String.self, forKey: .componentVersion)
        createdFiles = try values.decode([String].self, forKey: .createdFiles)
        createdDirectories = try values.decodeIfPresent([String].self, forKey: .createdDirectories) ?? []
        replacedFiles = try values.decode([ReplacedFileReceipt].self, forKey: .replacedFiles)
        configurationFingerprint = try values.decode(String.self, forKey: .configurationFingerprint)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        gameRootPath = try values.decode(String.self, forKey: .gameRootPath)
    }
}

nonisolated struct ReplacedFileReceipt: Codable, Sendable, Hashable {
    let relativePath: String
    let originalExisted: Bool
    let backupRelativePath: String?
    let originalSHA256: String?
    let replacementSHA256: String?
    let originalPermissions: Int?
}

/// Performs a declared, reversible per-game file transaction. The helper is
/// shared by temporal bridges, but it never discovers destination names from
/// arbitrary archive contents: callers must supply the component manifest's
/// explicit file subset.
nonisolated enum TemporalComponentInjection {
    static func inject(
        componentRoot: URL,
        reference: TemporalComponentReference,
        relativeFiles: [String],
        gameRoot: URL,
        applicationID: UUID,
        bridgeID: String,
        targetArchitecture: WindowsExecutableArchitecture,
        antiCheat: AntiCheatDetection,
        confirmUnknownInjectionPolicy: Bool,
        proxyStrategy: ProxyDLLStrategy,
        configurationFingerprint: String
    ) throws -> ManagedInjectionReceipt {
        guard !relativeFiles.isEmpty,
              relativeFiles.allSatisfy({
                  TemporalComponentSecurity.isSafeRelativePath($0)
                      && reference.requiredFiles.contains($0)
              }) else {
            throw TemporalInjectionError.componentUnavailable("The injection manifest contains an undeclared or unsafe file.")
        }
        if antiCheat.detected { throw TemporalInjectionError.antiCheatDetected }
        if !confirmUnknownInjectionPolicy { throw TemporalInjectionError.confirmationRequired }

        let root = gameRoot.standardizedFileURL
        let fileManager = FileManager.default
        guard (try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory) == true,
              (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw TemporalInjectionError.gameRootUnavailable(root)
        }

        let receiptID = UUID()
        let managementRoot = root.appending(path: ".boreal-temporal-upscaling", directoryHint: .isDirectory)
        let injectionsRoot = managementRoot.appending(path: "injections", directoryHint: .isDirectory)
        guard TemporalComponentSecurity.isSafeExistingDirectory(managementRoot),
              TemporalComponentSecurity.isSafeExistingDirectory(injectionsRoot) else {
            throw TemporalInjectionError.gameRootUnavailable(root)
        }
        let backupRoot = managementRoot.appending(path: "injections/\(receiptID.uuidString)/original", directoryHint: .isDirectory)
        let receiptURL = managementRoot.appending(path: "injections/\(receiptID.uuidString)/receipt.json")
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        var replaced: [ReplacedFileReceipt] = []
        var created: [String] = []
        var createdDirectories: [String] = []
        var destinations = Set<String>()
        var destinationNames = Set<String>()
        do {
            for relativeSource in relativeFiles {
                let source = componentRoot.appending(path: relativeSource)
                guard fileManager.isReadableFile(atPath: source.path),
                      destinations.insert(relativeSource).inserted else {
                    throw TemporalInjectionError.componentUnavailable(relativeSource)
                }
                let sourceName = URL(fileURLWithPath: relativeSource).lastPathComponent
                let destinationName: String = if case .named(let proxy) = proxyStrategy,
                                                 sourceName.lowercased() == "optiscaler.dll" {
                    proxy
                } else if bridgeID == "optiscaler" {
                    relativeSource
                } else {
                    sourceName
                }
                guard TemporalComponentSecurity.isSafeRelativePath(destinationName) else {
                    throw TemporalComponentError.unsafePath(destinationName)
                }
                guard destinationNames.insert(destinationName).inserted else {
                    throw TemporalInjectionError.componentUnavailable("The injection manifest maps multiple files to \(destinationName).")
                }
                let destination = root.appending(path: destinationName)
                let sourceValues = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard sourceValues.isRegularFile == true, sourceValues.isSymbolicLink != true else {
                    throw TemporalInjectionError.componentUnavailable(relativeSource)
                }
                if targetArchitecture != .unknown, source.pathExtension.lowercased() == "dll" {
                    let architecture = WindowsPEInspection.inspect(source).architecture
                    if architecture != .unknown, architecture != targetArchitecture {
                        throw TemporalInjectionError.wrongArchitecture(source)
                    }
                }

                let targetValues = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard targetValues.isSymbolicLink != true else {
                    throw TemporalInjectionError.gameFileIsSymlink(destination)
                }
                if fileManager.fileExists(atPath: destination.path),
                   targetValues.isRegularFile != true {
                    throw TemporalInjectionError.componentUnavailable("The injection destination is not a regular file: \(destinationName)")
                }
                if targetValues.isRegularFile == true, targetArchitecture != .unknown {
                    let architecture = WindowsPEInspection.inspect(destination).architecture
                    if architecture != .unknown, architecture != targetArchitecture {
                        throw TemporalInjectionError.wrongArchitecture(destination)
                    }
                }

                let replacementSHA = try RuntimeSecurity.sha256(of: source)
                let backupPath = backupRoot.appending(path: destinationName)
                var originalSHA: String?
                var originalPermissions: Int?
                if targetValues.isRegularFile == true {
                    try fileManager.createDirectory(at: backupPath.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fileManager.copyItem(at: destination, to: backupPath)
                    originalSHA = try RuntimeSecurity.sha256(of: destination)
                    originalPermissions = (try? fileManager.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber)?.intValue
                } else {
                    created.append(destinationName)
                }

                try ensureDestinationParent(
                    for: destinationName,
                    root: root,
                    fileManager: fileManager,
                    createdDirectories: &createdDirectories
                )
                try Data(contentsOf: source).write(to: destination, options: .atomic)
                replaced.append(ReplacedFileReceipt(
                    relativePath: destinationName,
                    originalExisted: targetValues.isRegularFile == true,
                    backupRelativePath: targetValues.isRegularFile == true
                        ? "injections/\(receiptID.uuidString)/original/\(destinationName)"
                        : nil,
                    originalSHA256: originalSHA,
                    replacementSHA256: replacementSHA,
                    originalPermissions: originalPermissions
                ))
            }

            let receipt = ManagedInjectionReceipt(
                id: receiptID,
                applicationID: applicationID,
                bridgeID: bridgeID,
                componentVersion: reference.version,
                createdFiles: created.sorted(),
                createdDirectories: createdDirectories.sorted(),
                replacedFiles: replaced.sorted { $0.relativePath < $1.relativePath },
                configurationFingerprint: configurationFingerprint,
                createdAt: Date(),
                gameRootPath: root.path
            )
            try TemporalComponentSecurity.makeEncoder().encode(receipt).write(to: receiptURL, options: .atomic)
            return receipt
        } catch {
            rollback(
                receiptID: receiptID,
                gameRoot: root,
                createdFiles: created,
                createdDirectories: createdDirectories,
                replacedFiles: replaced
            )
            throw error
        }
    }

    static func restore(_ receipt: ManagedInjectionReceipt, gameRoot: URL) throws {
        let fileManager = FileManager.default
        let root = gameRoot.standardizedFileURL
        guard root.path == receipt.gameRootPath else { throw TemporalInjectionError.receiptRootMismatch }
        let managementRoot = root.appending(path: ".boreal-temporal-upscaling", directoryHint: .isDirectory)
        let injectionsRoot = managementRoot.appending(path: "injections", directoryHint: .isDirectory)
        let receiptRoot = injectionsRoot.appending(path: receipt.id.uuidString, directoryHint: .isDirectory)
        guard TemporalComponentSecurity.isSafeExistingDirectory(managementRoot),
              TemporalComponentSecurity.isSafeExistingDirectory(injectionsRoot),
              TemporalComponentSecurity.isSafeExistingDirectory(receiptRoot) else {
            throw TemporalInjectionError.receiptRootMismatch
        }
        for item in receipt.replacedFiles {
            guard TemporalComponentSecurity.isSafeRelativePath(item.relativePath),
                  item.backupRelativePath.map(TemporalComponentSecurity.isSafeRelativePath) ?? true else {
                throw TemporalInjectionError.receiptRootMismatch
            }
            let destination = root.appending(path: item.relativePath)
            let targetValues = try destination.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard targetValues.isSymbolicLink != true else {
                throw TemporalInjectionError.gameFileIsSymlink(destination)
            }
            if let expected = item.replacementSHA256,
               fileManager.fileExists(atPath: destination.path),
               (try? RuntimeSecurity.sha256(of: destination)) != expected {
                throw TemporalInjectionError.modifiedManagedFile(destination)
            }
            if item.originalExisted, let backupRelativePath = item.backupRelativePath {
                let backup = managementRoot.appending(path: backupRelativePath)
                guard fileManager.isReadableFile(atPath: backup.path) else {
                    throw TemporalInjectionError.backupUnavailable(backup)
                }
                try Data(contentsOf: backup).write(to: destination, options: .atomic)
                if let permissions = item.originalPermissions {
                    try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: destination.path)
                }
            } else if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
        }
        removeCreatedDirectories(receipt.createdDirectories, from: root, fileManager: fileManager)
        let receiptURL = receiptRoot.appending(path: "receipt.json")
        if fileManager.fileExists(atPath: receiptURL.path) {
            try fileManager.removeItem(at: receiptURL)
        }
    }

    private static func rollback(
        receiptID: UUID,
        gameRoot: URL,
        createdFiles: [String],
        createdDirectories: [String],
        replacedFiles: [ReplacedFileReceipt]
    ) {
        let fileManager = FileManager.default
        for item in replacedFiles {
            let destination = gameRoot.appending(path: item.relativePath)
            if item.originalExisted, let backupRelativePath = item.backupRelativePath {
                let backup = gameRoot.appending(path: ".boreal-temporal-upscaling").appending(path: backupRelativePath)
                if fileManager.isReadableFile(atPath: backup.path) {
                    try? Data(contentsOf: backup).write(to: destination, options: .atomic)
                }
            } else if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
        }
        for path in createdFiles {
            let destination = gameRoot.appending(path: path)
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
        }
        removeCreatedDirectories(createdDirectories, from: gameRoot, fileManager: fileManager)
        let transaction = gameRoot.appending(path: ".boreal-temporal-upscaling/injections/\(receiptID.uuidString)")
        try? fileManager.removeItem(at: transaction)
    }

    private static func ensureDestinationParent(
        for destinationName: String,
        root: URL,
        fileManager: FileManager,
        createdDirectories: inout [String]
    ) throws {
        let components = destinationName.split(separator: "/")
        guard components.count > 1 else { return }
        var current = root
        for (index, component) in components.dropLast().enumerated() {
            let name = String(component)
            current.append(path: name, directoryHint: .isDirectory)
            let values = try current.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if fileManager.fileExists(atPath: current.path) {
                guard values.isSymbolicLink != true else {
                    throw TemporalInjectionError.gameFileIsSymlink(current)
                }
                guard values.isDirectory == true else {
                    throw TemporalInjectionError.componentUnavailable(
                        "The injection destination parent is not a directory: \(current.lastPathComponent)"
                    )
                }
            } else {
                try fileManager.createDirectory(at: current, withIntermediateDirectories: false)
                createdDirectories.append(components.prefix(index + 1).map(String.init).joined(separator: "/"))
            }
        }
    }

    private static func removeCreatedDirectories(
        _ paths: [String],
        from root: URL,
        fileManager: FileManager
    ) {
        for path in paths.sorted(by: { $0.split(separator: "/").count > $1.split(separator: "/").count }) {
            guard TemporalComponentSecurity.isSafeRelativePath(path) else { continue }
            let directory = root.appending(path: path, directoryHint: .isDirectory)
            guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true,
                  (try? fileManager.contentsOfDirectory(atPath: directory.path))?.isEmpty == true else {
                continue
            }
            try? fileManager.removeItem(at: directory)
        }
    }
}

nonisolated enum TemporalInjectionError: LocalizedError, Sendable {
    case componentUnavailable(String)
    case antiCheatDetected
    case confirmationRequired
    case gameRootUnavailable(URL)
    case gameFileIsSymlink(URL)
    case wrongArchitecture(URL)
    case receiptRootMismatch
    case modifiedManagedFile(URL)
    case backupUnavailable(URL)

    var errorDescription: String? {
        switch self {
        case .componentUnavailable(let value): "The managed temporal component is unavailable: \(value)"
        case .antiCheatDetected: "External DLL injection is disabled because anti-cheat or integrity protection may be active."
        case .confirmationRequired: "External DLL injection requires explicit confirmation for this game."
        case .gameRootUnavailable(let url): "The game directory is unavailable or is a symbolic link: \(url.path)"
        case .gameFileIsSymlink(let url): "Boreal will not replace a symbolic-link game file: \(url.path)"
        case .wrongArchitecture(let url): "The existing game DLL has an incompatible PE architecture: \(url.path)"
        case .receiptRootMismatch: "The managed injection receipt belongs to another game directory."
        case .modifiedManagedFile(let url): "The managed file was changed outside Boreal and was not overwritten: \(url.path)"
        case .backupUnavailable(let url): "The original backup is unavailable: \(url.path)"
        }
    }
}

// MARK: - Managed DLSS runtime replacement

nonisolated enum DLSSRuntimeSource: String, Codable, CaseIterable, Sendable, Hashable {
    case gameOriginal
    case borealManaged
    case userImported
}

nonisolated struct DLSSRuntimeInstallation: Codable, Sendable, Hashable {
    let detectedVersion: String?
    let originalFileURL: URL
    let originalSHA256: String
    let activeFileURL: URL
    let activeSHA256: String
    let source: DLSSRuntimeSource
}

nonisolated struct DLSSRuntimeReplacementReceipt: Codable, Sendable, Hashable {
    let applicationID: UUID?
    let originalFileName: String
    let originalSHA256: String
    let originalBackupRelativePath: String
    let originalPermissions: Int?
    let activeSHA256: String
    let managedVersion: String?
    let createdAt: Date
}

nonisolated enum DLSSRuntimeError: LocalizedError, Sendable {
    case originalNotFound(URL)
    case invalidOriginal(URL)
    case wrongArchitecture(URL)
    case managedComponentUnavailable(String)
    case backupMissing(URL)
    case modifiedActiveFile(URL)
    case unsafeGameRoot(URL)

    var errorDescription: String? {
        switch self {
        case .originalNotFound(let root): "No nvngx_dlss.dll or nvngx.dll was found in \(root.path)."
        case .invalidOriginal(let url): "The original DLSS file is missing, not regular, or is a symbolic link: \(url.path)"
        case .wrongArchitecture(let url): "The managed DLSS file has an incompatible PE architecture: \(url.path)"
        case .managedComponentUnavailable(let value): "The managed DLSS runtime is unavailable: \(value)"
        case .backupMissing(let url): "The original DLSS backup is missing: \(url.path)"
        case .modifiedActiveFile(let url): "The active DLSS file was changed outside Boreal and was not overwritten: \(url.path)"
        case .unsafeGameRoot(let url): "The game directory is unavailable or is a symbolic link: \(url.path)"
        }
    }
}

actor DLSSRuntimeManager {
    private let store: ManagedTemporalComponentStore
    private let fileManager: FileManager

    init(store: ManagedTemporalComponentStore, fileManager: FileManager = .default) {
        self.store = store
        self.fileManager = fileManager
    }

    func installedReference(version: String? = nil) -> TemporalComponentReference? {
        store.reference(for: .dlssRuntime, version: version)
    }

    func install(from source: URL, version: String, licenseMetadata: String? = nil) throws -> TemporalComponentReference {
        try store.install(id: .dlssRuntime, version: version, source: source, sourceKind: .userImport, licenseMetadata: licenseMetadata)
    }

    func install(
        candidate: DLSSRuntimeCandidate,
        from source: URL
    ) throws -> TemporalComponentReference {
        if let expectedSize = candidate.expectedSize {
            let actualSize = try TemporalComponentSecurity.directoryByteSize(
                source.standardizedFileURL,
                excluding: ["component.json"]
            )
            guard expectedSize >= 0, actualSize == expectedSize else {
                throw TemporalComponentError.invalidComponent(
                    "The component size does not match the provider metadata."
                )
            }
        }
        guard let expected = candidate.expectedSHA256 else {
            return try store.install(
                id: .dlssRuntime,
                version: candidate.version,
                source: source,
                sourceKind: candidate.source,
                licenseMetadata: candidate.licenseMetadata
            )
        }
        let actual = try TemporalComponentSecurity.directorySHA256(
            source.standardizedFileURL,
            excluding: ["component.json"]
        )
        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            throw TemporalComponentError.checksumMismatch(expected: expected, actual: actual)
        }
        return try store.install(
            id: .dlssRuntime,
            version: candidate.version,
            source: source,
            sourceKind: candidate.source,
            licenseMetadata: candidate.licenseMetadata
        )
    }

    func detect(in gameRoot: URL) -> DLSSRuntimeInstallation? {
        let root = gameRoot.standardizedFileURL
        guard (try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory) == true,
              (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return nil }
        let managementRoot = root.appending(path: ".boreal-temporal-upscaling", directoryHint: .isDirectory)
        let receiptURL = managementRoot.appending(path: "dlss-runtime.json")
        if let data = try? Data(contentsOf: receiptURL),
           let receipt = try? TemporalComponentSecurity.makeDecoder().decode(DLSSRuntimeReplacementReceipt.self, from: data) {
            guard TemporalComponentSecurity.isSafeRelativePath(receipt.originalFileName),
                  !receipt.originalFileName.contains("/"),
                  TemporalComponentSecurity.isSafeRelativePath(receipt.originalBackupRelativePath) else {
                return nil
            }
            let active = root.appending(path: receipt.originalFileName)
            guard fileManager.isReadableFile(atPath: active.path),
                  (try? active.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile) == true,
                  (try? active.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                  let activeSHA = try? RuntimeSecurity.sha256(of: active) else { return nil }
            let original = root.appending(path: receipt.originalFileName)
            return DLSSRuntimeInstallation(
                detectedVersion: receipt.managedVersion,
                originalFileURL: original,
                originalSHA256: receipt.originalSHA256,
                activeFileURL: active,
                activeSHA256: activeSHA,
                source: receipt.managedVersion == nil ? .gameOriginal : .borealManaged
            )
        }
        guard let file = dlssFile(in: root), let sha = try? RuntimeSecurity.sha256(of: file) else { return nil }
        return DLSSRuntimeInstallation(
            detectedVersion: WindowsPEInspection.inspect(file).version,
            originalFileURL: file,
            originalSHA256: sha,
            activeFileURL: file,
            activeSHA256: sha,
            source: .gameOriginal
        )
    }

    func backupOriginal(in gameRoot: URL, applicationID: UUID? = nil) throws -> DLSSRuntimeInstallation {
        let root = try validatedRoot(gameRoot)
        if let existing = readReceipt(in: root) {
            guard let installation = detect(in: root) else { throw DLSSRuntimeError.backupMissing(root) }
            _ = existing
            return installation
        }
        guard let original = dlssFile(in: root) else { throw DLSSRuntimeError.originalNotFound(root) }
        let values = try original.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw DLSSRuntimeError.invalidOriginal(original) }
        let originalSHA = try RuntimeSecurity.sha256(of: original)
        let managedRoot = root.appending(path: ".boreal-temporal-upscaling", directoryHint: .isDirectory)
        let dlssManagementRoot = managedRoot.appending(path: "dlss-runtime", directoryHint: .isDirectory)
        guard TemporalComponentSecurity.isSafeExistingDirectory(managedRoot),
              TemporalComponentSecurity.isSafeExistingDirectory(dlssManagementRoot) else {
            throw DLSSRuntimeError.unsafeGameRoot(root)
        }
        let backupRelativePath = "dlss-runtime/original/\(original.lastPathComponent)"
        let backup = managedRoot.appending(path: backupRelativePath)
        do {
            try fileManager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: original, to: backup)
            let receipt = DLSSRuntimeReplacementReceipt(
                applicationID: applicationID,
                originalFileName: original.lastPathComponent,
                originalSHA256: originalSHA,
                originalBackupRelativePath: backupRelativePath,
                originalPermissions: (try? fileManager.attributesOfItem(atPath: original.path)[.posixPermissions] as? NSNumber)?.intValue,
                activeSHA256: originalSHA,
                managedVersion: nil,
                createdAt: Date()
            )
            try TemporalComponentSecurity.makeEncoder().encode(receipt).write(to: managedRoot.appending(path: "dlss-runtime.json"), options: .atomic)
        } catch {
            try? fileManager.removeItem(at: backup)
            throw error
        }
        return DLSSRuntimeInstallation(
            detectedVersion: WindowsPEInspection.inspect(original).version,
            originalFileURL: original,
            originalSHA256: originalSHA,
            activeFileURL: original,
            activeSHA256: originalSHA,
            source: .gameOriginal
        )
    }

    func installManagedVersion(
        _ reference: TemporalComponentReference,
        in gameRoot: URL,
        applicationID: UUID? = nil,
        targetArchitecture: WindowsExecutableArchitecture = .unknown
    ) throws -> DLSSRuntimeInstallation {
        guard reference.componentID == TemporalComponentID.dlssRuntime.rawValue, store.contains(reference) else {
            throw DLSSRuntimeError.managedComponentUnavailable(reference.id)
        }
        let root = try validatedRoot(gameRoot)
        let managedRoot = root.appending(path: ".boreal-temporal-upscaling", directoryHint: .isDirectory)
        guard TemporalComponentSecurity.isSafeExistingDirectory(managedRoot),
              TemporalComponentSecurity.isSafeExistingDirectory(managedRoot.appending(path: "dlss-runtime", directoryHint: .isDirectory)) else {
            throw DLSSRuntimeError.unsafeGameRoot(root)
        }
        let componentRoot = store.componentURL(.dlssRuntime, version: reference.version)
        let source = reference.requiredFiles
            .map { componentRoot.appending(path: $0) }
            .first { $0.lastPathComponent.lowercased() == "nvngx_dlss.dll" || $0.lastPathComponent.lowercased() == "nvngx.dll" }
        guard let source, fileManager.isReadableFile(atPath: source.path) else {
            throw DLSSRuntimeError.managedComponentUnavailable("The component does not contain nvngx_dlss.dll or nvngx.dll.")
        }
        let sourceValues = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard sourceValues.isRegularFile == true, sourceValues.isSymbolicLink != true else {
            throw DLSSRuntimeError.managedComponentUnavailable("The managed DLSS file is not a regular file.")
        }
        let sourceInspection = WindowsPEInspection.inspect(source)
        guard sourceInspection.isPE, sourceInspection.architecture != .unknown else {
            throw DLSSRuntimeError.managedComponentUnavailable("The managed DLSS file is not a valid x86 or x86_64 PE image.")
        }
        if targetArchitecture != .unknown, sourceInspection.architecture != targetArchitecture {
            throw DLSSRuntimeError.wrongArchitecture(source)
        }
        let original: DLSSRuntimeInstallation
        if readReceipt(in: root) != nil {
            guard let existing = detect(in: root) else { throw DLSSRuntimeError.backupMissing(root) }
            original = existing
        } else {
            original = try backupOriginal(in: root, applicationID: applicationID)
        }
        let destination = root.appending(path: original.originalFileURL.lastPathComponent)
        let currentSHA = try RuntimeSecurity.sha256(of: destination)
        if let receipt = readReceipt(in: root), receipt.managedVersion != nil, currentSHA != receipt.activeSHA256 {
            throw DLSSRuntimeError.modifiedActiveFile(destination)
        }
        let previousData = try Data(contentsOf: destination)
        let previousPermissions = (try? fileManager.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber)?.intValue
        let oldReceipt = readReceipt(in: root)
        do {
            try Data(contentsOf: source).write(to: destination, options: .atomic)
            let activeSHA = try RuntimeSecurity.sha256(of: destination)
            let receipt = DLSSRuntimeReplacementReceipt(
                applicationID: applicationID ?? oldReceipt?.applicationID,
                originalFileName: original.originalFileURL.lastPathComponent,
                originalSHA256: original.originalSHA256,
                originalBackupRelativePath: oldReceipt?.originalBackupRelativePath ?? "dlss-runtime/original/\(original.originalFileURL.lastPathComponent)",
                originalPermissions: oldReceipt?.originalPermissions,
                activeSHA256: activeSHA,
                managedVersion: reference.version,
                createdAt: oldReceipt?.createdAt ?? Date()
            )
            let managedRoot = root.appending(path: ".boreal-temporal-upscaling", directoryHint: .isDirectory)
            try TemporalComponentSecurity.makeEncoder().encode(receipt).write(to: managedRoot.appending(path: "dlss-runtime.json"), options: .atomic)
        } catch {
            try? previousData.write(to: destination, options: .atomic)
            if let previousPermissions { try? fileManager.setAttributes([.posixPermissions: previousPermissions], ofItemAtPath: destination.path) }
            throw error
        }
        let activeSHA = try RuntimeSecurity.sha256(of: destination)
        return DLSSRuntimeInstallation(
            detectedVersion: sourceInspection.version,
            originalFileURL: original.originalFileURL,
            originalSHA256: original.originalSHA256,
            activeFileURL: destination,
            activeSHA256: activeSHA,
            source: .borealManaged
        )
    }

    func restoreOriginal(in gameRoot: URL) throws -> DLSSRuntimeInstallation {
        let root = try validatedRoot(gameRoot)
        let managedRoot = root.appending(path: ".boreal-temporal-upscaling", directoryHint: .isDirectory)
        guard TemporalComponentSecurity.isSafeExistingDirectory(managedRoot),
              TemporalComponentSecurity.isSafeExistingDirectory(managedRoot.appending(path: "dlss-runtime", directoryHint: .isDirectory)) else {
            throw DLSSRuntimeError.unsafeGameRoot(root)
        }
        guard let receipt = readReceipt(in: root) else {
            guard let detected = detect(in: root) else { throw DLSSRuntimeError.originalNotFound(root) }
            return detected
        }
        guard TemporalComponentSecurity.isSafeRelativePath(receipt.originalFileName),
              !receipt.originalFileName.contains("/"),
              TemporalComponentSecurity.isSafeRelativePath(receipt.originalBackupRelativePath) else {
            throw DLSSRuntimeError.backupMissing(root)
        }
        let active = root.appending(path: receipt.originalFileName)
        if fileManager.fileExists(atPath: active.path) {
            let activeValues = try active.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard activeValues.isRegularFile == true, activeValues.isSymbolicLink != true else {
                throw DLSSRuntimeError.invalidOriginal(active)
            }
        }
        if fileManager.fileExists(atPath: active.path),
           let currentSHA = try? RuntimeSecurity.sha256(of: active),
           currentSHA != receipt.activeSHA256 {
            throw DLSSRuntimeError.modifiedActiveFile(active)
        }
        let backup = root.appending(path: ".boreal-temporal-upscaling").appending(path: receipt.originalBackupRelativePath)
        guard fileManager.isReadableFile(atPath: backup.path) else { throw DLSSRuntimeError.backupMissing(backup) }
        let backupValues = try backup.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard backupValues.isRegularFile == true, backupValues.isSymbolicLink != true else {
            throw DLSSRuntimeError.backupMissing(backup)
        }
        try Data(contentsOf: backup).write(to: active, options: .atomic)
        if let permissions = receipt.originalPermissions { try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: active.path) }
        let restoredSHA = try RuntimeSecurity.sha256(of: active)
        guard restoredSHA == receipt.originalSHA256 else { throw DLSSRuntimeError.modifiedActiveFile(active) }
        try? fileManager.removeItem(at: managedRoot.appending(path: "dlss-runtime.json"))
        return DLSSRuntimeInstallation(
            detectedVersion: WindowsPEInspection.inspect(active).version,
            originalFileURL: active,
            originalSHA256: restoredSHA,
            activeFileURL: active,
            activeSHA256: restoredSHA,
            source: .gameOriginal
        )
    }

    func removeManagedOverride(in gameRoot: URL) throws -> DLSSRuntimeInstallation { try restoreOriginal(in: gameRoot) }

    func validate(in gameRoot: URL) -> Bool {
        guard let installation = detect(in: gameRoot) else { return false }
        guard (try? RuntimeSecurity.sha256(of: installation.activeFileURL)) == installation.activeSHA256 else {
            return false
        }
        let root = gameRoot.standardizedFileURL
        guard let receipt = readReceipt(in: root) else { return true }
        return receipt.activeSHA256 == installation.activeSHA256
    }

    private func dlssFile(in root: URL) -> URL? {
        ["nvngx_dlss.dll", "nvngx.dll"].map { root.appending(path: $0) }.first {
            fileManager.isReadableFile(atPath: $0.path)
                && (try? $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile) == true
                && (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
        }
    }

    private func readReceipt(in root: URL) -> DLSSRuntimeReplacementReceipt? {
        let managedRoot = root.appending(path: ".boreal-temporal-upscaling", directoryHint: .isDirectory)
        guard TemporalComponentSecurity.isSafeExistingDirectory(managedRoot),
              TemporalComponentSecurity.isSafeExistingDirectory(managedRoot.appending(path: "dlss-runtime", directoryHint: .isDirectory)) else { return nil }
        let url = root.appending(path: ".boreal-temporal-upscaling/dlss-runtime.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? TemporalComponentSecurity.makeDecoder().decode(DLSSRuntimeReplacementReceipt.self, from: data)
    }

    private func validatedRoot(_ gameRoot: URL) throws -> URL {
        let root = gameRoot.standardizedFileURL
        guard (try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory) == true,
              (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw DLSSRuntimeError.unsafeGameRoot(root)
        }
        return root
    }
}

// MARK: - Inspector and diagnostics projection

nonisolated struct TemporalComponentStatus: Sendable, Hashable {
    let installed: Bool
    let version: String?
    let sha256: String?
    let source: TemporalComponentSource?
    let licenseMetadata: String?

    init(reference: TemporalComponentReference?) {
        installed = reference != nil
        version = reference?.version
        sha256 = reference?.sha256
        source = reference?.source
        licenseMetadata = reference?.licenseMetadata
    }

    init(installation: DLSSRuntimeInstallation?) {
        installed = installation != nil
        version = installation?.detectedVersion
        sha256 = installation?.activeSHA256
        source = nil
        licenseMetadata = nil
    }
}

nonisolated struct NGXDebugIndicatorState: Sendable, Hashable {
    let available: Bool
    let enabled: Bool?
    let detail: String
}

nonisolated struct NGXDebugIndicatorReceipt: Codable, Sendable, Hashable {
    let registryPath: String
    let previousValue: String?
    let previousType: String?
    let wasPresent: Bool
    let enabledAt: Date
}

nonisolated struct TemporalUpscalingInspectorSnapshot: Sendable, Hashable {
    let game: GameUpscalingCapabilities
    let dlssRuntime: DLSSRuntimeInstallation?
    let dlssRuntimeStatus: TemporalComponentStatus
    let managedDLSSRuntime: TemporalComponentStatus
    let dlsstweaks: TemporalComponentStatus
    let dlsstweaksCapabilities: DLSSTweaksCapabilities?
    let optiScaler: TemporalComponentStatus
    let metalFX: MetalFXBridgeCapabilities
    let temporalPlan: TemporalUpscalingPlan
    let graphicsStack: GraphicsStack
    let runtimeDescription: String
    let ngxDebugIndicator: NGXDebugIndicatorState
}
