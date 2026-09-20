import Foundation
import Observation
import os

@MainActor
@Observable
final class FrameGenerationCoordinator {
    static let shared = FrameGenerationCoordinator()

    private(set) var states: [UUID: FrameGenerationState] = [:]
    private(set) var runtimeEvidenceByApplication: [UUID: FrameGenerationRuntimeEvidence] = [:]
    private var providers: [UUID: any FrameGenerationProvider] = [:]
    private let logger = Logger(subsystem: "STDMSolution.Boreal", category: "FrameGenerationCoordinator")

    private init() {}

    func start(
        applicationID: UUID,
        gamePID: pid_t?,
        gameRoot: URL,
        executable: URL,
        configuration: OptiScalerConfiguration
    ) {
        logger.info(
            "In-process Frame Generation start requested; appID=\(applicationID.uuidString, privacy: .public), gamePID=\(gamePID ?? 0, privacy: .public), backend=optiScaler, executable=\(executable.path, privacy: .public)"
        )
        retireProvider(for: applicationID)

        guard configuration.enabled, configuration.frameGeneration.mode == .optiFG else {
            states[applicationID] = .inactive
            return
        }

        let provider = OptiScalerFrameGenerationProvider()
        let providerToken = ObjectIdentifier(provider)
        providers[applicationID] = provider
        states[applicationID] = .preparing
        runtimeEvidenceByApplication[applicationID] = nil
        provider.runtimeErrorHandler = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleRuntimeError(error, applicationID: applicationID)
            }
        }
        provider.runtimeEvidenceHandler = { [weak self] evidence in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrent(providerToken, for: applicationID) else { return }
                self.runtimeEvidenceByApplication[applicationID] = evidence
            }
        }
        provider.stateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrent(providerToken, for: applicationID) else { return }
                self.states[applicationID] = state
            }
        }
        Task { @MainActor [weak self] in
            do {
                try await provider.start(
                    gamePID: gamePID,
                    gameRoot: gameRoot,
                    executable: executable,
                    configuration: configuration
                )
                guard let self else {
                    await provider.stop()
                    return
                }
                guard self.isCurrent(provider, for: applicationID) else {
                    await provider.stop()
                    return
                }
                self.states[applicationID] = .injected
                self.logger.info(
                    "OptiScaler Frame Generation monitor is running; appID=\(applicationID.uuidString, privacy: .public)"
                )
            } catch {
                guard let self else {
                    await provider.stop()
                    return
                }
                guard self.isCurrent(provider, for: applicationID) else {
                    await provider.stop()
                    return
                }
                self.states[applicationID] = .failed(error.localizedDescription)
                self.logger.error(
                    "OptiScaler Frame Generation failed to start; appID=\(applicationID.uuidString, privacy: .public), error=\(error.localizedDescription, privacy: .public)"
                )
                self.providers[applicationID] = nil
                await provider.stop()
            }
        }
    }

    func stop(applicationID: UUID) async {
        guard let provider = detachProvider(for: applicationID) else { return }
        await provider.stop()
    }

    func updateGamePIDs(applicationID: UUID, gamePIDs: [Int32]) {
        providers[applicationID]?.updateGamePIDs(gamePIDs)
    }

    func requestStop(applicationID: UUID) {
        guard let provider = detachProvider(for: applicationID) else { return }
        Task { await provider.stop() }
    }

    func stopAll() async {
        for applicationID in Array(providers.keys) {
            await stop(applicationID: applicationID)
        }
    }

    func state(for applicationID: UUID) -> FrameGenerationState {
        states[applicationID] ?? .inactive
    }

    func runtimeEvidence(for applicationID: UUID) -> FrameGenerationRuntimeEvidence? {
        runtimeEvidenceByApplication[applicationID]
    }

    func capabilities() -> FrameGenerationCapabilities {
        OptiScalerFrameGenerationProvider().capabilities()
    }

    private func handleRuntimeError(_ error: Error, applicationID: UUID) {
        guard let provider = providers.removeValue(forKey: applicationID) else { return }
        logger.error(
            "Frame Generation provider reported a runtime error; appID=\(applicationID.uuidString, privacy: .public), error=\(error.localizedDescription, privacy: .public)"
        )
        states[applicationID] = .failed(error.localizedDescription)
        runtimeEvidenceByApplication[applicationID] = nil
        Task { await provider.stop() }
    }

    private func retireProvider(for applicationID: UUID) {
        guard let provider = detachProvider(for: applicationID) else { return }
        Task { await provider.stop() }
    }

    private func detachProvider(for applicationID: UUID) -> (any FrameGenerationProvider)? {
        let provider = providers.removeValue(forKey: applicationID)
        states[applicationID] = .inactive
        runtimeEvidenceByApplication[applicationID] = nil
        return provider
    }

    private func isCurrent(_ provider: any FrameGenerationProvider, for applicationID: UUID) -> Bool {
        guard let current = providers[applicationID] else { return false }
        return (current as AnyObject) === (provider as AnyObject)
    }

    private func isCurrent(_ providerToken: ObjectIdentifier, for applicationID: UUID) -> Bool {
        guard let current = providers[applicationID] else { return false }
        return ObjectIdentifier(current as AnyObject) == providerToken
    }
}
