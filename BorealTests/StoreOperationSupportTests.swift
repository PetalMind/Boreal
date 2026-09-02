import Foundation
import Testing
@testable import Boreal

struct StoreOperationSupportTests {
    @Test func parsesHelperPercentagesAndClampsPresentationProgress() throws {
        let update = try #require(StoreProgressParser.update(
            from: Data("Downloading chunk [42.5%] at 18.2 MiB/s\n".utf8),
            provider: "GOG"
        ))

        #expect(update.fractionCompleted == 0.425)
        #expect(update.message == "Downloading game files")
        #expect(update.phase == .downloading)
        #expect(update.transferRate == "18.2 MiB/s")
        #expect(update.networkBytesPerSecond == 18.2 * 1_048_576)
        #expect(update.diskBytesPerSecond == nil)
        #expect(update.rawDetail == "Downloading chunk [42.5%] at 18.2 MiB/s")
        #expect(StoreGameOperationProgress(message: "test", fractionCompleted: 1.4).clampedFraction == 1)
        #expect(update.transferredBytes == nil)
    }

    @Test func turnsDiskTelemetryIntoAnInstallingStageAndKeepsRawLogInDetails() throws {
        let update = try #require(StoreProgressParser.update(
            from: Data("[PROGRESS] INFO: + Disk - 23.57 MiB/s (write) / 0.00 MiB/s (read)\n".utf8),
            provider: "GOG"
        ))

        #expect(update.phase == .installing)
        #expect(update.message == "Writing game files")
        #expect(update.transferRate == "23.6 MiB/s")
        #expect(update.diskBytesPerSecond == 23.57 * 1_048_576)
        #expect(update.networkBytesPerSecond == nil)
        #expect(update.rawDetail?.hasPrefix("[PROGRESS] INFO:") == true)
    }

    @Test func parsesAndMergesNativeGOGDLProgressBlock() throws {
        let update = try #require(StoreProgressParser.update(
            from: Data("""
            INFO [PROGRESS]: = Progress: 25.00 536870912/2147483648, Running for: 00:00:32, ETA: 00:01:36
            INFO [PROGRESS]: = Downloaded: 512.00 MiB, Written: 512.00 MiB
            INFO [PROGRESS]: + Download - 5.30 MiB/s (raw) / 12.00 MiB/s (decompressed)
            INFO [PROGRESS]: + Disk - 8.10 MiB/s (write) / 0.00 MiB/s (read)
            """.utf8),
            provider: "GOG"
        ))

        #expect(update.fractionCompleted == 0.25)
        #expect(update.transferredBytes == 536_870_912)
        #expect(update.totalBytes == 2_147_483_648)
        #expect(update.estimatedTimeRemaining == "00:01:36")
        #expect(update.networkBytesPerSecond == 5.30 * 1_048_576)
        #expect(update.diskBytesPerSecond == 8.10 * 1_048_576)
        #expect(update.phase == .downloading)
        #expect(update.rawDetail?.contains("Progress: 25.00") == true)
        #expect(update.rawDetail?.contains("Disk - 8.10 MiB/s") == true)
    }

    @Test func keepsGOGDLProgressWhenOneSampleIsSplitAcrossCallbacks() throws {
        let accumulator = StoreProgressAccumulator(provider: "GOG")
        let progress = try #require(accumulator.update(from: Data(
            "INFO [PROGRESS]: = Progress: 25.00 536870912/2147483648, ETA: 00:01:36\n".utf8
        )))
        #expect(progress.fractionCompleted == 0.25)
        #expect(progress.estimatedTimeRemaining == "00:01:36")

        let download = try #require(accumulator.update(from: Data(
            "INFO [PROGRESS]: + Download - 5.30 MiB/s (raw) / 12.00 MiB/s (decompressed)\n".utf8
        )))
        #expect(download.fractionCompleted == 0.25)
        #expect(download.networkBytesPerSecond == 5.30 * 1_048_576)
        #expect(download.estimatedTimeRemaining == "00:01:36")

        #expect(accumulator.update(from: Data(
            "INFO [PROGRESS]: + Disk - 8.10 MiB/s (wr".utf8
        )) == nil)
        let disk = try #require(accumulator.update(from: Data("ite) / 0.00 MiB/s (read)\n".utf8)))
        #expect(disk.fractionCompleted == 0.25)
        #expect(disk.networkBytesPerSecond == 5.30 * 1_048_576)
        #expect(disk.diskBytesPerSecond == 8.10 * 1_048_576)
        #expect(disk.estimatedTimeRemaining == "00:01:36")
        #expect(disk.phase == .downloading)
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
        #expect(update.transferredBytes == 2_254_857_830)
        #expect(update.totalBytes == 5_798_205_850)
    }

    @Test func parsesSteamProgressAndAHelperLineSplitAcrossCallbacks() throws {
        let steam = try #require(StoreProgressParser.update(
            from: Data("Update state 0x61, downloading, progress: 37.5\n".utf8),
            provider: "Steam"
        ))
        #expect(steam.fractionCompleted == 0.375)
        #expect(steam.phase == .downloading)

        let accumulator = StoreProgressAccumulator(provider: "GOG")
        #expect(accumulator.update(from: Data("Downloading 38% 2.1 Gi".utf8)) == nil)
        let update = try #require(accumulator.update(from: Data("B / 5.4 GiB ETA: 1 min\n".utf8)))
        #expect(update.fractionCompleted == 0.38)
        #expect(update.transferredBytes == 2_254_857_830)
        #expect(update.totalBytes == 5_798_205_850)
    }

    @Test func derivesPercentageFromNumericAmountsWhenHelperOmitsIt() {
        let progress = StoreGameOperationProgress(
            message: "Downloading",
            fractionCompleted: nil,
            transferredBytes: 25,
            totalBytes: 100
        )
        #expect(progress.clampedFraction == 0.25)
        #expect(progress.remainingBytes == 75)
    }

    @Test func parsesSteamBytesWhenTheUnitAppearsOnlyOnce() throws {
        let update = try #require(StoreProgressParser.update(
            from: Data("Update state downloading, progress: 37.5 (1234 / 5678 KB)\n".utf8),
            provider: "Steam"
        ))
        #expect(update.transferredBytes == 1_234_000)
        #expect(update.totalBytes == 5_678_000)
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
