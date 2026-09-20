import Foundation
import os
#if canImport(Darwin)
import Darwin
#endif

@MainActor
final class OptiScalerFrameGenerationProvider: FrameGenerationProvider {
    let identifier = "optiScaler"
    var runtimeErrorHandler: (@Sendable (Error) -> Void)?
    var stateHandler: (@Sendable (FrameGenerationState) -> Void)?
    var runtimeEvidenceHandler: (@Sendable (FrameGenerationRuntimeEvidence) -> Void)?

    private let logger = Logger(subsystem: "STDMSolution.Boreal", category: "OptiScalerFrameGeneration")
    private var monitorTask: Task<Void, Never>?
    private var gamePIDs: [pid_t] = []
    private var gameRoot: URL?
    private var logURL: URL?
    private var startedAt: Date?
    private var didRecordEarlyFailure = false
    private var didRecordHealthy = false
    private var hasObservedGameProcess = false
    private var observedProcessHandoff = false
    private var lastObservedPIDs: Set<pid_t> = []

    func capabilities() -> FrameGenerationCapabilities {
        FrameGenerationCapabilities(
            isSupported: true,
            reason: "OptiFG is an experimental DX12 in-process backend; actual availability depends on the game's upscaler data and renderer."
        )
    }

    func start(
        gamePID: pid_t?,
        gameRoot: URL,
        executable: URL,
        configuration: OptiScalerConfiguration
    ) async throws {
        await stop()
        guard configuration.enabled, configuration.frameGeneration.mode == .optiFG else {
            throw FrameGenerationError.optiScalerNotConfigured
        }

        self.gamePIDs = gamePID.map { [$0] } ?? []
        self.gameRoot = gameRoot.standardizedFileURL
        self.startedAt = Date()
        self.didRecordEarlyFailure = false
        self.didRecordHealthy = false
        self.hasObservedGameProcess = false
        self.observedProcessHandoff = false
        self.lastObservedPIDs = []
        self.logURL = OptiScalerLogLocator.existingLog(gameRoot: gameRoot)
        publish(.injected)
        publishEvidence(.noLog, detail: nil)
        logger.info(
            "OptiScaler Frame Generation monitor started; executable=\(executable.path, privacy: .public), gameRoot=\(gameRoot.path, privacy: .public), gamePID=\(gamePID ?? 0, privacy: .public)"
        )

        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func updateGamePIDs(_ gamePIDs: [Int32]) {
        let normalized = Set(gamePIDs.filter { $0 > 0 })
        if !normalized.isEmpty {
            if hasObservedGameProcess, normalized.isDisjoint(with: lastObservedPIDs) {
                observedProcessHandoff = true
            }
            hasObservedGameProcess = true
            lastObservedPIDs = normalized
            self.gamePIDs = normalized.sorted()
        } else if hasObservedGameProcess {
            self.gamePIDs = []
        }
    }

    func stop() async {
        // The coordinator also calls stop for an intentional user stop. Early
        // failure accounting therefore happens only from poll(), after the
        // provider has observed the game process exit itself.
        monitorTask?.cancel()
        monitorTask = nil
        gamePIDs = []
        gameRoot = nil
        logURL = nil
        startedAt = nil
        didRecordEarlyFailure = false
        didRecordHealthy = false
        hasObservedGameProcess = false
        observedProcessHandoff = false
        lastObservedPIDs = []
    }

    private func poll() async {
        guard let root = gameRoot else { return }
        if logURL == nil { logURL = OptiScalerLogLocator.existingLog(gameRoot: root) }

        let data = logURL.flatMap { try? Data(contentsOf: $0) }
        let parsedState = data.map { OptiScalerLogParser.state(for: $0) } ?? .noLog
        switch parsedState {
        case .noLog:
            publish(.injected)
        case .waitingForUpscaler:
            publish(.waitingForUpscaler)
        case .available:
            publish(.frameGenerationAvailable)
        case .initialized:
            publish(.optiFGInitialized)
        case .active:
            publish(.active)
        case .degraded(let reason):
            publish(.degraded(reason))
        }
        publishEvidence(
            parsedState,
            detail: data == nil && logURL != nil ? FrameGenerationError.optiScalerLogUnavailable.localizedDescription : nil
        )

        if [.initialized, .active].contains(where: { parsedState == $0 }), !didRecordHealthy {
            OptiScalerRecoveryManager.recordHealthy(gameRoot: root)
            didRecordHealthy = true
        }

        if let startedAt,
           Date().timeIntervalSince(startedAt) <= 15,
           processState == .exited,
           hasObservedGameProcess,
           !observedProcessHandoff,
           case .degraded = parsedState,
           !didRecordEarlyFailure {
            let recovery = OptiScalerRecoveryManager.recordEarlyFailure(
                gameRoot: root,
                startedAt: startedAt
            )
            didRecordEarlyFailure = true
            let suffix = recovery.disabled ? " OptiFG was disabled for the next launch after repeated early failures." : ""
            publish(.degraded("The game exited before OptiFG reported a usable state.\(suffix)"))
        }
    }

    private func publish(_ state: FrameGenerationState) {
        stateHandler?(state)
    }

    private var processState: FrameGenerationProcessState {
        guard hasObservedGameProcess else { return .unknown }
        return gamePIDs.contains(where: processIsAlive) ? .running : .exited
    }

    private func processIsAlive(_ pid: pid_t) -> Bool {
        let result = kill(pid, 0)
        return result == 0 || errno == EPERM
    }

    private func publishEvidence(_ state: OptiScalerLogState, detail: String?) {
        let log: FrameGenerationLogEvidence = switch state {
        case .noLog: .unknown
        case .waitingForUpscaler: .waiting
        case .available: .available
        case .initialized: .initialized
        case .active: .active
        case .degraded: .failed
        }
        runtimeEvidenceHandler?(
            FrameGenerationRuntimeEvidence(
                installation: OptiScalerRecoveryManager.installationState(gameRoot: gameRoot ?? URL(fileURLWithPath: "/")),
                process: processState,
                log: log,
                detail: detail
            )
        )
    }
}
