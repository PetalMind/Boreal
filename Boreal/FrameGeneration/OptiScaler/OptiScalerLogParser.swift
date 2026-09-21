import Foundation

nonisolated enum OptiScalerLogState: Sendable, Equatable, Hashable {
    case noLog
    case waitingForUpscaler
    case available
    case initialized
    case active
    case degraded(String)
}

/// OptiScaler's log is intentionally treated as diagnostic evidence, not as
/// proof that every game can produce usable frame-generation inputs. Messages
/// are matched conservatively and the UI keeps the experimental status visible.
nonisolated enum OptiScalerLogParser {
    static func state(for data: Data) -> OptiScalerLogState {
        let text = String(decoding: data, as: UTF8.self)
        return state(for: text)
    }

    static func state(for text: String) -> OptiScalerLogState {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).lowercased() }
        guard !lines.isEmpty else { return .noLog }

        if let failure = lines.reversed().first(where: {
            ($0.contains("error") || $0.contains("failed") || $0.contains("exception") || $0.contains("crash"))
                && ($0.contains("optifg") || $0.contains("framegen") || $0.contains("frame generation") || $0.contains("frame-generation"))
        }) {
            return .degraded(failure.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let lastContextCreation = lines.lastIndex(where: {
            $0.contains("d3d12_createcontext") && $0.contains("created")
        })
        let lastMissingContext = lines.lastIndex(where: {
            $0.contains("no fg context") || $0.contains("no frame generation context")
        })
        if let lastMissingContext,
           lastContextCreation.map({ lastMissingContext > $0 }) ?? true {
            return .degraded("FSR Frame Generation lost its DX12 context.")
        }
        if let lastContextCreation {
            let afterContextCreation = lines.dropFirst(lastContextCreation + 1)
            if afterContextCreation.contains(where: {
                $0.contains("fghooks::fgpresent") || $0.contains("frame generation present")
            }) {
                return .active
            }
            return .initialized
        }
        if lines.contains(where: { $0.contains("device captured") && $0.contains("d3d12") }) {
            return .available
        }

        if lines.contains(where: {
            ($0.contains("framegen") || $0.contains("frame generation") || $0.contains("optifg"))
                && $0.contains("active")
        }) {
            return .active
        }

        if lines.contains(where: {
            ($0.contains("framegen") || $0.contains("frame generation") || $0.contains("optifg"))
                && ($0.contains("initialized") || $0.contains("initialised") || $0.contains("enabled"))
        }) {
            return .initialized
        }

        if lines.contains(where: {
            ($0.contains("framegen") || $0.contains("frame generation") || $0.contains("optifg"))
                && ($0.contains("available") || $0.contains("loaded") || $0.contains("ready"))
        }) {
            return .available
        }

        if lines.contains(where: {
            $0.contains("upscaler") && ($0.contains("wait") || $0.contains("missing") || $0.contains("not found"))
        }) {
            return .waitingForUpscaler
        }

        return .noLog
    }
}

nonisolated enum OptiScalerLogLocator {
    static func candidates(gameRoot: URL) -> [URL] {
        [
            gameRoot.appending(path: "OptiScaler.log"),
            gameRoot.appending(path: "OptiScaler/OptiScaler.log")
        ]
    }

    static func existingLog(gameRoot: URL, fileManager: FileManager = .default) -> URL? {
        candidates(gameRoot: gameRoot).first { fileManager.isReadableFile(atPath: $0.path) }
    }
}
