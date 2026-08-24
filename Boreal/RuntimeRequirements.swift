import Foundation

nonisolated protocol RuntimeRequirementChecking: Sendable {
    func isSatisfied(_ requirement: RuntimeRequirement) async -> Bool
}

nonisolated struct RuntimeRequirementChecker: RuntimeRequirementChecking {
    let processExecutor: any ProcessExecuting

    func isSatisfied(_ requirement: RuntimeRequirement) async -> Bool {
        switch requirement {
        case .gStreamerFramework:
            return FileManager.default.fileExists(atPath: "/Library/Frameworks/GStreamer.framework")
        case .rosetta2:
            #if arch(arm64)
            let directory = FileManager.default.temporaryDirectory.appending(path: "Boreal-Rosetta-\(UUID().uuidString)")
            let request = ProcessLaunchRequest(
                executable: URL(fileURLWithPath: "/usr/bin/arch"),
                arguments: ["-x86_64", "/usr/bin/true"],
                environment: ProcessInfo.processInfo.environment,
                stdoutLog: directory.appending(path: "stdout.log"),
                stderrLog: directory.appending(path: "stderr.log")
            )
            guard let receipt = try? await processExecutor.launch(request),
                  let result = try? await processExecutor.waitForExit(receipt.id) else { return false }
            return result.exitCode == 0
            #else
            return true
            #endif
        }
    }
}
