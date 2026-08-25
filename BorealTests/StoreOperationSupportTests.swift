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
        #expect(update.message == "Downloading from GOG… 42%")
        #expect(StoreGameOperationProgress(message: "test", fractionCompleted: 1.4).clampedFraction == 1)
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
}
