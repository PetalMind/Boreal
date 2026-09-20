import Foundation
import Observation
import os

@MainActor
@Observable
final class FrameGenerationCoordinator {
    static let shared = FrameGenerationCoordinator()

    private(set) var states: [UUID: FrameGenerationState] = [:]
    private(set) var statisticsByApplication: [UUID: FrameGenerationStatistics] = [:]
    private var providers: [UUID: any FrameGenerationProvider] = [:]
    private var statisticsTasks: [UUID: Task<Void, Never>] = [:]
    private let logger = Logger(subsystem: "STDMSolution.Boreal", category: "FrameGenerationCoordinator")

    private init() {}

    func start(
        applicationID: UUID,
        gamePID: pid_t,
        configuration: FrameGenerationRuntimeConfiguration
    ) {
        logger.info(
            "Frame Generation coordinator start requested; appID=\(applicationID.uuidString, privacy: .public), gamePID=\(gamePID, privacy: .public), backend=\(configuration.backend.rawValue, privacy: .public)"
        )
        retireProvider(for: applicationID)
        guard configuration.enabled, configuration.backend != .off else {
            logger.info("Frame Generation coordinator inactive because configuration is disabled; appID=\(applicationID.uuidString, privacy: .public)")
            states[applicationID] = .inactive
            return
        }

        let provider: any FrameGenerationProvider
        switch configuration.backend {
        case .off:
            states[applicationID] = .inactive
            return
        case .metalFX:
            provider = MetalFXFrameGenerationProvider()
        }

        providers[applicationID] = provider
        states[applicationID] = .preparing
        provider.runtimeErrorHandler = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleRuntimeError(error, applicationID: applicationID)
            }
        }
        statisticsTasks[applicationID]?.cancel()
        statisticsTasks[applicationID] = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                self.statisticsByApplication[applicationID] = provider.statistics()
            }
        }

        Task { @MainActor [weak self] in
            do {
                try await provider.start(gamePID: gamePID, configuration: configuration)
                guard let self else {
                    await provider.stop()
                    return
                }
                guard self.isCurrent(provider, for: applicationID) else {
                    await provider.stop()
                    return
                }
                self.states[applicationID] = .running
                self.logger.info("Frame Generation provider is running; appID=\(applicationID.uuidString, privacy: .public), gamePID=\(gamePID, privacy: .public)")
            } catch {
                guard let self else {
                    await provider.stop()
                    return
                }
                guard self.isCurrent(provider, for: applicationID) else {
                    await provider.stop()
                    return
                }
                self.states[applicationID] = self.state(for: error)
                self.logger.error(
                    "Frame Generation provider failed to start; appID=\(applicationID.uuidString, privacy: .public), gamePID=\(gamePID, privacy: .public), error=\(error.localizedDescription, privacy: .public)"
                )
                self.statisticsTasks[applicationID]?.cancel()
                self.statisticsTasks[applicationID] = nil
                self.providers[applicationID] = nil
                await provider.stop()
            }
        }
    }

    func stop(applicationID: UUID) async {
        guard let provider = detachProvider(for: applicationID) else { return }
        await provider.stop()
    }

    /// Synchronous lifecycle boundary for callers that cannot await while they
    /// are finalizing a process session. The provider is detached immediately;
    /// its asynchronous resources are released in the background.
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

    func statistics(for applicationID: UUID) -> FrameGenerationStatistics {
        statisticsByApplication[applicationID] ?? FrameGenerationStatistics()
    }

    func capabilities(for backend: FrameGenerationBackend) -> FrameGenerationCapabilities {
        switch backend {
        case .off:
            FrameGenerationCapabilities(isSupported: true, reason: nil)
        case .metalFX:
            MetalFXFrameGenerationSupport.capabilities()
        }
    }

    private func handleRuntimeError(_ error: Error, applicationID: UUID) {
        guard let provider = providers.removeValue(forKey: applicationID) else { return }
        logger.error(
            "Frame Generation provider reported a runtime error; appID=\(applicationID.uuidString, privacy: .public), error=\(error.localizedDescription, privacy: .public)"
        )
        statisticsTasks[applicationID]?.cancel()
        statisticsTasks[applicationID] = nil
        states[applicationID] = state(for: error)
        statisticsByApplication[applicationID] = nil
        Task { await provider.stop() }
    }

    private func retireProvider(for applicationID: UUID) {
        guard let provider = detachProvider(for: applicationID) else { return }
        Task { await provider.stop() }
    }

    private func detachProvider(for applicationID: UUID) -> (any FrameGenerationProvider)? {
        statisticsTasks[applicationID]?.cancel()
        statisticsTasks[applicationID] = nil
        let provider = providers.removeValue(forKey: applicationID)
        states[applicationID] = .inactive
        statisticsByApplication[applicationID] = nil
        return provider
    }

    private func isCurrent(_ provider: any FrameGenerationProvider, for applicationID: UUID) -> Bool {
        guard let current = providers[applicationID] else { return false }
        return (current as AnyObject) === (provider as AnyObject)
    }

    private func state(for error: Error) -> FrameGenerationState {
        switch error {
        case FrameGenerationError.unsupportedHardware,
             FrameGenerationError.unsupportedOS,
             FrameGenerationError.screenCapturePermissionDenied,
             FrameGenerationError.metalDeviceUnavailable,
             FrameGenerationError.gameWindowNotFound,
             FrameGenerationError.motionEstimatorUnavailable:
            return .unavailable(error.localizedDescription)
        default:
            return .failed(error.localizedDescription)
        }
    }
}
