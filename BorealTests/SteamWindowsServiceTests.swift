import Foundation
import Testing
@testable import Boreal

@Suite(.serialized)
struct SteamWindowsServiceTests {
    @Test func rejectsMissingCredentialsBeforeStartingSteamCMD() async {
        let root = FileManager.default.temporaryDirectory.appending(path: "BorealSteamCMDTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SteamWindowsService(applicationSupportURL: root, processExecutor: UnusedProcessExecutor())
        do {
            _ = try await service.downloadWindowsGame(appID: "730", destination: root.appending(path: "Game"), credentials: SteamCMDCredentials(username: "", password: "", guardCode: "")) { _ in }
            Issue.record("Expected missing credentials error")
        } catch let error as SteamWindowsError {
            #expect(error.localizedDescription.contains("username"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private struct UnusedProcessExecutor: ProcessExecuting {
    func launch(_ request: ProcessLaunchRequest) async throws -> ProcessLaunchReceipt { throw CocoaError(.featureUnsupported) }
    func waitForExit(_ id: UUID) async throws -> ProcessExecutionResult { throw CocoaError(.featureUnsupported) }
    func state(of id: UUID) async throws -> ProcessExecutionState { throw CocoaError(.featureUnsupported) }
    func terminate(_ id: UUID) async throws { }
    func forceTerminate(_ id: UUID) async throws { }
}
