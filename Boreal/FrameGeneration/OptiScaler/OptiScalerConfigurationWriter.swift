import Foundation

nonisolated enum OptiScalerConfigurationWriter {
    static func managedValues(from template: Data?) -> [String: String] {
        guard let template,
              let source = String(data: template, encoding: .utf8) else { return [:] }
        let managedKeys: [String: Set<String>] = [
            "Upscalers": ["dx12upscaler"],
            "FrameGen": ["enabled", "fginput", "fgoutput", "debugview", "preserveswapchain", "skipresizebuffers"],
            "OptiFG": ["hudfix", "hudlimit"],
            "Log": ["logtofile"],
            "Plugins": ["path", "loadasiplugins"]
        ]
        var section = ""
        var values: [String: String] = [:]
        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                continue
            }
            guard let separator = line.firstIndex(of: "="),
                  !line.hasPrefix("#"), !line.hasPrefix(";") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces).lowercased()
            guard let allowed = managedKeys.first(where: { $0.key.caseInsensitiveCompare(section) == .orderedSame })?.value,
                  allowed.contains(key) else { continue }
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            let canonicalSection = managedKeys.keys.first(where: { $0.caseInsensitiveCompare(section) == .orderedSame }) ?? section
            values["\(canonicalSection).\(key)"] = value
        }
        return values
    }

    static func render(
        template: Data?,
        configuration: OptiScalerConfiguration
    ) -> Data {
        let source = template.flatMap { String(data: $0, encoding: .utf8) }
            ?? "# Boreal-managed OptiScaler configuration\n"
        var lines = source.components(separatedBy: .newlines)
        if lines.last == "" { lines.removeLast() }

        let frameGenerationEnabled = configuration.frameGenerationEnabled
        var frameValues: [(String, String)] = [
            ("Enabled", frameGenerationEnabled ? "true" : "false"),
            ("FGInput", configuration.frameGeneration.input.iniValue),
            ("FGOutput", configuration.frameGeneration.output.iniValue),
            ("DebugView", configuration.frameGeneration.debugView ? "true" : "false")
        ]
        if let preserveSwapChain = configuration.preserveSwapChain {
            frameValues.append(("PreserveSwapChain", preserveSwapChain ? "true" : "false"))
        }
        if let skipResizeBuffers = configuration.skipResizeBuffers {
            frameValues.append(("SkipResizeBuffers", skipResizeBuffers ? "true" : "false"))
        }
        var optiFGValues: [(String, String)] = [
            ("HUDFix", hudFixValue(configuration.frameGeneration.hudHandling))
        ]
        if configuration.frameGeneration.hudHandling == .compatibility {
            optiFGValues.append(("HUDLimit", "1"))
        }

        upsert(section: "FrameGen", values: frameValues, in: &lines)
        upsert(
            section: "Upscalers",
            values: [("Dx12Upscaler", configuration.upscalerInput.iniValue)],
            in: &lines
        )
        upsert(section: "OptiFG", values: optiFGValues, in: &lines)
        upsert(
            section: "Log",
            values: [("LogToFile", configuration.frameGeneration.loggingEnabled ? "true" : "false")],
            in: &lines
        )
        upsert(
            section: "Plugins",
            values: [("Path", ".\\plugins"), ("LoadAsiPlugins", "true")],
            in: &lines
        )
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private static func hudFixValue(_ handling: OptiScalerHUDHandling) -> String {
        switch handling {
        case .automatic: "auto"
        case .off: "false"
        case .compatibility: "true"
        }
    }

    private static func upsert(
        section: String,
        values: [(String, String)],
        in lines: inout [String]
    ) {
        let header = "[\(section)]"
        guard let headerIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(header) == .orderedSame
        }) else {
            if !lines.isEmpty, !lines.last!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.append("") }
            lines.append(header)
            lines.append(contentsOf: values.map { "\($0.0)=\($0.1)" })
            return
        }

        let nextSection = lines[(headerIndex + 1)...].firstIndex(where: {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.hasPrefix("[") && value.hasSuffix("]")
        }) ?? lines.endIndex
        for (key, value) in values {
            let keyIndex = lines[(headerIndex + 1)..<nextSection].firstIndex(where: { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("#"), !trimmed.hasPrefix(";") else { return false }
                return trimmed.split(separator: "=", maxSplits: 1).first.map {
                    $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(key) == .orderedSame
                } ?? false
            })
            if let keyIndex {
                let indentation = lines[keyIndex].prefix { $0 == " " || $0 == "\t" }
                lines[keyIndex] = "\(indentation)\(key)=\(value)"
            } else {
                lines.insert("\(key)=\(value)", at: nextSection)
            }
        }
    }
}

nonisolated enum ExistingDLLClassification: String, Codable, Sendable, Hashable {
    case boreal
    case optiScaler
    case reshade
    case knownWrapper
    case unknown

    var displayName: String {
        switch self {
        case .boreal: "Boreal-managed"
        case .optiScaler: "OptiScaler"
        case .reshade: "ReShade"
        case .knownWrapper: "Known wrapper"
        case .unknown: "Unknown third-party DLL"
        }
    }
}

nonisolated struct OptiScalerProxyCandidate: Sendable, Hashable {
    let name: String
    let classification: ExistingDLLClassification?
    let isAvailable: Bool
    let detail: String
}

nonisolated struct OptiScalerProxyInspection: Sendable, Hashable {
    let selectedName: String?
    let candidates: [OptiScalerProxyCandidate]

    var summary: String {
        if let selectedName {
            return "OptiScaler proxy: \(selectedName)"
        }
        return "No safe OptiScaler proxy was found next to the graphics executable."
    }
}

nonisolated struct OptiScalerProxyResolution: Sendable, Hashable {
    let name: String
    let replacedExistingManagedFile: Bool
    let existingClassification: ExistingDLLClassification?
    let skippedCandidates: [OptiScalerProxyCandidate]
}

/// Finds the executable that is most likely to create the game's graphics
/// device. Launchers and bootstrap executables are intentionally deprioritized.
nonisolated enum GraphicsExecutableResolver {
    static func resolve(
        gameRoot: URL,
        preferred: URL?,
        fileManager: FileManager = .default
    ) -> URL {
        var candidates: [URL] = if let enumerator = fileManager.enumerator(
            at: gameRoot.standardizedFileURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            enumerator.compactMap { $0 as? URL }.filter {
                $0.pathExtension.caseInsensitiveCompare("exe") == .orderedSame
                    && fileManager.isReadableFile(atPath: $0.path)
            }
        } else {
            []
        }
        if let preferred,
           preferred.pathExtension.caseInsensitiveCompare("exe") == .orderedSame,
           fileManager.isReadableFile(atPath: preferred.path),
           !candidates.contains(where: { $0.standardizedFileURL == preferred.standardizedFileURL }) {
            candidates.append(preferred.standardizedFileURL)
        }
        return candidates.sorted { lhs, rhs in
            let leftScore = score(lhs)
            let rightScore = score(rhs)
            return leftScore == rightScore ? lhs.path < rhs.path : leftScore > rightScore
        }.first ?? preferred?.standardizedFileURL ?? gameRoot.appending(path: "game.exe")
    }

    private static func score(_ url: URL) -> Int {
        let path = url.path.lowercased()
        var score = 0
        if path.contains("/binaries/win64/") { score += 100 }
        if path.contains("/game/") { score += 25 }
        if path.contains("shipping") { score += 35 }
        if path.contains("-win64") { score += 20 }
        if path.contains("launcher") || path.contains("bootstrap") || path.contains("play") { score -= 70 }
        if path.contains("setup") || path.contains("install") || path.contains("unins") || path.contains("crash") { score -= 100 }
        return score
    }
}

/// Resolves a proxy next to the actual graphics executable. Existing
/// third-party DLLs are never overwritten unless their receipt proves that
/// Boreal owns the previous OptiScaler installation.
nonisolated enum OptiScalerProxyResolver {
    private static let automaticCandidates = ["dxgi.dll", "version.dll", "winmm.dll", "d3d12.dll"]

    static func inspect(
        gameExecutable: URL,
        strategy: ProxyDLLStrategy,
        fileManager: FileManager = .default
    ) -> OptiScalerProxyInspection {
        let directory = gameExecutable.deletingLastPathComponent().standardizedFileURL
        let names: [String] = switch strategy {
        case .automatic: automaticCandidates
        case .named(let value): [value]
        }
        let candidates = names.compactMap { candidate -> OptiScalerProxyCandidate? in
            let normalized = candidate.lowercased().hasSuffix(".dll") ? candidate : "\(candidate).dll"
            guard TemporalComponentSecurity.isSafeRelativePath(normalized),
                  normalized.split(separator: "/").count == 1 else { return nil }
            let target = directory.appending(path: normalized)
            guard fileManager.fileExists(atPath: target.path) else {
                return OptiScalerProxyCandidate(
                    name: normalized,
                    classification: nil,
                    isAvailable: true,
                    detail: "Available"
                )
            }
            let classification = classify(target: target, directory: directory, fileManager: fileManager)
            let available = classification == .boreal
            let detail = available
                ? "Existing Boreal-managed proxy can be replaced transactionally."
                : "Skipped: existing \(classification.displayName) was left untouched."
            return OptiScalerProxyCandidate(
                name: normalized,
                classification: classification,
                isAvailable: available,
                detail: detail
            )
        }
        return OptiScalerProxyInspection(
            selectedName: candidates.first(where: { $0.isAvailable })?.name,
            candidates: candidates
        )
    }

    static func resolveExecutable(
        gameRoot: URL,
        preferred: URL?,
        fileManager: FileManager = .default
    ) -> URL {
        GraphicsExecutableResolver.resolve(
            gameRoot: gameRoot,
            preferred: preferred,
            fileManager: fileManager
        )
    }

    static func resolve(
        gameExecutable: URL,
        strategy: ProxyDLLStrategy,
        fileManager: FileManager = .default
    ) -> OptiScalerProxyResolution? {
        let inspection = inspect(gameExecutable: gameExecutable, strategy: strategy, fileManager: fileManager)
        guard let selected = inspection.candidates.first(where: { $0.isAvailable }) else { return nil }
        return OptiScalerProxyResolution(
            name: selected.name,
            replacedExistingManagedFile: selected.classification == .boreal,
            existingClassification: selected.classification,
            skippedCandidates: inspection.candidates.filter { !$0.isAvailable }
        )
    }

    static func applyWineOverride(
        to values: inout [String: String],
        gameExecutable: URL,
        strategy: ProxyDLLStrategy
    ) -> OptiScalerProxyResolution? {
        let gameRoot = gameExecutable.deletingLastPathComponent().standardizedFileURL
        guard !OptiScalerRecoveryManager.shouldDisable(gameRoot: gameRoot) else { return nil }
        guard let resolution = resolve(gameExecutable: gameExecutable, strategy: strategy) else { return nil }
        let library = URL(fileURLWithPath: resolution.name)
            .deletingPathExtension()
            .lastPathComponent
            .lowercased()
        let existing = values["WINEDLLOVERRIDES"]?.split(separator: ";").map(String.init) ?? []
        let preserved = existing.filter { entry in
            let name = entry.split(separator: "=", maxSplits: 1).first.map(String.init)?.lowercased() ?? ""
            return name != library
        }
        values["WINEDLLOVERRIDES"] = (["\(library)=n,b"] + preserved).joined(separator: ";")
        return resolution
    }

    private static func classify(
        target: URL,
        directory: URL,
        fileManager: FileManager
    ) -> ExistingDLLClassification {
        if isManagedOptiScalerFile(target, gameRoot: directory, fileManager: fileManager) {
            return .boreal
        }
        let siblingNames = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ))?.map { $0.lastPathComponent.lowercased() } ?? []
        if siblingNames.contains(where: { $0 == "reshade.ini" || $0.hasPrefix("reshade") }) {
            return .reshade
        }
        if siblingNames.contains(where: { $0.hasPrefix("specialk") || $0.contains("dgvoodoo") || $0 == "dxwrapper.dll" }) {
            return .knownWrapper
        }
        if siblingNames.contains("optiscaler.ini") || target.lastPathComponent.lowercased().contains("optiscaler") {
            return .optiScaler
        }
        if let data = try? Data(contentsOf: target) {
            let signature = String(decoding: data.prefix(4 * 1024 * 1024), as: UTF8.self).lowercased()
            if signature.contains("reshade") { return .reshade }
            if signature.contains("special k") || signature.contains("specialk") { return .knownWrapper }
            if signature.contains("optiscaler") { return .optiScaler }
        }
        return .unknown
    }

    private static func isManagedOptiScalerFile(
        _ target: URL,
        gameRoot: URL,
        fileManager: FileManager
    ) -> Bool {
        let injections = gameRoot.appending(path: ".boreal-temporal-upscaling/injections", directoryHint: .isDirectory)
        guard let entries = try? fileManager.contentsOfDirectory(at: injections, includingPropertiesForKeys: [.isDirectoryKey]) else { return false }
        let decoder = TemporalComponentSecurity.makeDecoder()
        for entry in entries {
            let receiptURL = entry.appending(path: "receipt.json")
            guard let data = try? Data(contentsOf: receiptURL),
                  let receipt = try? decoder.decode(ManagedInjectionReceipt.self, from: data),
                  receipt.bridgeID == "optiscaler",
                  receipt.gameRootPath == gameRoot.standardizedFileURL.path else { continue }
            if receipt.replacedFiles.contains(where: { $0.relativePath.caseInsensitiveCompare(target.lastPathComponent) == .orderedSame }) {
                return true
            }
        }
        return false
    }
}
