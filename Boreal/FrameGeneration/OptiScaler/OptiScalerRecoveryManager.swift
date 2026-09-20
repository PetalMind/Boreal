import Foundation

nonisolated struct OptiScalerRecoveryState: Codable, Sendable, Hashable {
    var consecutiveEarlyFailures = 0
    var disabled = false
    var lastFailureAt: Date?
    var lastHealthyAt: Date?
}

/// Keeps crash protection separate from the component and its immutable
/// receipt. A repeated early failure rolls back only the managed OptiScaler
/// transaction and suppresses later OptiFG launches; it never removes save
/// data, the Wine prefix, or the managed component from disk.
nonisolated enum OptiScalerRecoveryManager {
    private static let fileName = "optifg-recovery.json"
    private static let failureLimit = 2
    private static let earlyFailureWindow: TimeInterval = 15

    static func shouldDisable(gameRoot: URL, fileManager: FileManager = .default) -> Bool {
        read(gameRoot: gameRoot, fileManager: fileManager)?.disabled == true
    }

    static func installationState(
        gameRoot: URL,
        fileManager: FileManager = .default
    ) -> FrameGenerationInstallationState {
        let root = gameRoot.standardizedFileURL
        let injections = root.appending(path: ".boreal-temporal-upscaling/injections", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: injections.path) else { return .notManaged }
        guard isSafeDirectory(injections, fileManager: fileManager),
              let entries = try? fileManager.contentsOfDirectory(
            at: injections,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return .unknown }
        let decoder = TemporalComponentSecurity.makeDecoder()
        guard let receipt = entries.compactMap({ entry -> ManagedInjectionReceipt? in
            guard let data = try? Data(contentsOf: entry.appending(path: "receipt.json")),
                  let receipt = try? decoder.decode(ManagedInjectionReceipt.self, from: data),
                  receipt.bridgeID == "optiscaler",
                  receipt.gameRootPath == root.path else { return nil }
            return receipt
        }).max(by: { $0.createdAt < $1.createdAt }) else {
            return .notManaged
        }

        for file in receipt.replacedFiles {
            let target = root.appending(path: file.relativePath)
            guard fileManager.isReadableFile(atPath: target.path),
                  let expected = file.replacementSHA256,
                  (try? RuntimeSecurity.sha256(of: target)) == expected else {
                return .modified
            }
        }
        return .managed
    }

    private static func isSafeDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    static func recordEarlyFailure(
        gameRoot: URL,
        startedAt: Date,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> OptiScalerRecoveryState {
        var state = read(gameRoot: gameRoot, fileManager: fileManager) ?? OptiScalerRecoveryState()
        guard now.timeIntervalSince(startedAt) <= earlyFailureWindow else { return state }
        state.consecutiveEarlyFailures += 1
        state.disabled = state.consecutiveEarlyFailures >= failureLimit
        state.lastFailureAt = now
        write(state, gameRoot: gameRoot, fileManager: fileManager)
        if state.disabled {
            rollbackManagedOptiScalerInstallation(gameRoot: gameRoot, fileManager: fileManager)
        }
        return state
    }

    static func recordHealthy(
        gameRoot: URL,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) {
        var state = read(gameRoot: gameRoot, fileManager: fileManager) ?? OptiScalerRecoveryState()
        state.consecutiveEarlyFailures = 0
        state.disabled = false
        state.lastHealthyAt = now
        write(state, gameRoot: gameRoot, fileManager: fileManager)
    }

    static func reset(
        gameRoot: URL,
        fileManager: FileManager = .default
    ) {
        let url = recoveryURL(gameRoot: gameRoot)
        try? fileManager.removeItem(at: url)
    }

    /// Restores managed OptiScaler transactions from newest to oldest. This
    /// matters when the user reconfigured the component more than once: the
    /// newest receipt may contain the previous Boreal-managed DLL as its
    /// backup, so the complete stack must be unwound to reach the user's file.
    static func rollbackManagedOptiScalerInstallation(
        gameRoot: URL,
        fileManager: FileManager = .default
    ) {
        let injections = gameRoot.standardizedFileURL
            .appending(path: ".boreal-temporal-upscaling/injections", directoryHint: .isDirectory)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: injections,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }
        let decoder = TemporalComponentSecurity.makeDecoder()
        let receipts = entries.compactMap { entry -> ManagedInjectionReceipt? in
            guard let data = try? Data(contentsOf: entry.appending(path: "receipt.json")),
                  let receipt = try? decoder.decode(ManagedInjectionReceipt.self, from: data),
                  receipt.bridgeID == "optiscaler",
                  receipt.gameRootPath == gameRoot.standardizedFileURL.path else { return nil }
            return receipt
        }.sorted { $0.createdAt > $1.createdAt }

        for receipt in receipts {
            try? TemporalComponentInjection.restore(receipt, gameRoot: gameRoot)
        }
    }

    private static func read(gameRoot: URL, fileManager: FileManager) -> OptiScalerRecoveryState? {
        let url = recoveryURL(gameRoot: gameRoot)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(OptiScalerRecoveryState.self, from: data)
    }

    private static func write(
        _ state: OptiScalerRecoveryState,
        gameRoot: URL,
        fileManager: FileManager
    ) {
        let managementRoot = gameRoot.appending(path: ".boreal-temporal-upscaling", directoryHint: .isDirectory)
        guard TemporalComponentSecurity.isSafeExistingDirectory(managementRoot) else { return }
        do {
            try fileManager.createDirectory(at: managementRoot, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(state)
            try data.write(to: recoveryURL(gameRoot: gameRoot), options: .atomic)
        } catch {
            // Recovery is a safety enhancement. A filesystem failure must not
            // turn a normal game launch into a fabricated OptiScaler failure.
        }
    }

    private static func recoveryURL(gameRoot: URL) -> URL {
        gameRoot.standardizedFileURL
            .appending(path: ".boreal-temporal-upscaling", directoryHint: .isDirectory)
            .appending(path: fileName)
    }
}
