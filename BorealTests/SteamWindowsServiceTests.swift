import Foundation
import Testing
@testable import Boreal

@Suite(.serialized)
struct SteamWindowsServiceTests {
    @Test func downloadsOfficialBootstrapperAndReturnsContainedSteamClient() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BorealSteamWindowsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let prefix = root.appending(path: "Environment/prefix")
        let logs = root.appending(path: "Environment/Logs")
        let steam = prefix.appending(path: "drive_c/Program Files (x86)/Steam/steam.exe")
        try FileManager.default.createDirectory(at: steam.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try Data([0x4D, 0x5A]).write(to: steam)

        let runtime = InstalledRuntime(
            id: "runtime", displayName: "Runtime", wineVersion: "test",
            rootURL: root.appending(path: "Runtime"),
            wineExecutable: root.appending(path: "Runtime/wine"),
            wineServerExecutable: root.appending(path: "Runtime/wineserver"),
            wineBootExecutable: root.appending(path: "Runtime/wineboot"),
            architecture: .x86_64, requirements: []
        )
        let environment = ManagedBorealEnvironment(
            id: UUID(), configuration: EnvironmentConfiguration(name: "Steam"), runtimeID: runtime.id,
            rootURL: root.appending(path: "Environment"), prefixURL: prefix, logsURL: logs, state: .ready
        )
        let session = WindowsProcessSession(
            id: UUID(), environmentID: environment.id, launcherPID: 42, startedAt: .now,
            stdoutLog: logs.appending(path: "stdout.log"), stderrLog: logs.appending(path: "stderr.log")
        )
        let result = ProcessExecutionResult(
            pid: 41, startedAt: .now, terminatedAt: .now, exitCode: 0, terminationReason: 1,
            stdoutLog: logs.appending(path: "installer.stdout.log"), stderrLog: logs.appending(path: "installer.stderr.log")
        )
        let commit = InstallationCommit(environment: environment, runtime: runtime, executable: steam, firstLaunch: session, installerResult: result)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SteamInstallerURLProtocol.self]
        let service = SteamWindowsService(
            applicationSupportURL: root,
            installer: SteamInstallerMock(commit: commit),
            session: URLSession(configuration: configuration)
        )

        let prepared = try await service.prepareClient { _ in }

        #expect(prepared.steamExecutable == steam.resolvingSymlinksInPath())
        let downloaded = root.appending(path: "Installers/Steam/SteamSetup.exe")
        #expect(FileManager.default.fileExists(atPath: downloaded.path))
        let header = try Data(contentsOf: downloaded).prefix(2)
        #expect(header == Data([0x4D, 0x5A]))
    }
}

private struct SteamInstallerMock: Installing {
    let commit: InstallationCommit
    func install(_ installer: URL, name: String, progress: @escaping @Sendable (InstallationStage) async -> Void) async throws -> InstallationCommit {
        #expect(name == "Steam")
        #expect(installer.lastPathComponent == "SteamSetup.exe")
        await progress(.startingInstaller)
        return commit
    }
}

private nonisolated final class SteamInstallerURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = Data([0x4D, 0x5A])
        data.append(Data(repeating: 0, count: 1_000_001))
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/octet-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
