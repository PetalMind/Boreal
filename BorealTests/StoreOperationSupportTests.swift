import Foundation
import Testing
@testable import Boreal

struct StoreOperationSupportTests {
    @Test func parsesHelperPercentagesAndClampsPresentationProgress() throws {
        let update = try #require(StoreProgressParser.update(
            from: Data("Downloading chunk [42.5%] at 18.2 MiB/s\n".utf8),
            provider: "GOG"
        ))

        #expect(update.fractionCompleted == 0.42)
        #expect(update.message == "Downloading game files")
        #expect(update.phase == .downloading)
        #expect(update.transferRate == "18.2 MiB/s")
        #expect(update.networkBytesPerSecond == 18.2 * 1_048_576)
        #expect(update.diskBytesPerSecond == nil)
        #expect(update.rawDetail == "Downloading chunk [42.5%] at 18.2 MiB/s")
        #expect(StoreGameOperationProgress(message: "test", fractionCompleted: 1.4).clampedFraction == 1)
    }

    @Test func turnsDiskTelemetryIntoAnInstallingStageAndKeepsRawLogInDetails() throws {
        let update = try #require(StoreProgressParser.update(
            from: Data("[PROGRESS] INFO: + Disk - 23.57 MiB/s (write) / 0.00 MiB/s (receive)\n".utf8),
            provider: "GOG"
        ))

        #expect(update.phase == .installing)
        #expect(update.message == "Writing game files")
        #expect(update.transferRate == "23.6 MiB/s")
        #expect(update.diskBytesPerSecond == 23.57 * 1_048_576)
        #expect(update.networkBytesPerSecond == 0)
        #expect(update.rawDetail?.hasPrefix("[PROGRESS] INFO:") == true)
    }

    @Test func extractsAmountsAndEstimatedTimeForTheCompactSummary() throws {
        let update = try #require(StoreProgressParser.update(
            from: Data("Downloading 38% 2.1 GiB / 5.4 GiB at 23.6 MiB/s ETA: 1 min 24 sec\n".utf8),
            provider: "GOG"
        ))

        #expect(update.fractionCompleted == 0.38)
        #expect(update.transferred == "2.1 GiB")
        #expect(update.total == "5.4 GiB")
        #expect(update.transferRate == "23.6 MiB/s")
        #expect(update.estimatedTimeRemaining == "1 min 24 sec")
    }

    @Test func cancellationTerminatesAttachedHelperProcess() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "trap 'exit 0' TERM; while :; do sleep 0.05; done"]
        let box = CancellableStoreProcess()
        try process.run()
        box.attach(process)
        #expect(process.isRunning)

        box.cancel()
        for _ in 0..<100 where process.isRunning {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(!process.isRunning)
    }

    @Test func calculatesAllocatedGameStorageFromRealFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "BorealStorageTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: 32_768).write(to: root.appending(path: "game.bin"))

        let bytes = try #require(GameStorage.allocatedSize(of: root))
        #expect(bytes >= 32_768)
        #expect(GameStorage.availableCapacity(at: root) != nil)
    }
}
