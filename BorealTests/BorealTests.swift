//
//  BorealTests.swift
//  BorealTests
//
//  Created by Dominik on 24/08/2026.
//

import Foundation
import Testing
@testable import Boreal

struct BorealTests {
    @Test func sha256UsesStreamingCompatibleDigest() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "boreal-sha-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: url)
        #expect(try RuntimeSecurity.sha256(of: url) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func processExecutorCapturesPIDLogsAndExitCode() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "boreal-process-\(UUID().uuidString)")
        let executor = SystemProcessExecutor()
        let receipt = try await executor.launch(ProcessLaunchRequest(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo BOREAL_TEST_STARTED; echo BOREAL_TEST_DIAGNOSTIC >&2; exit 42"],
            environment: ProcessInfo.processInfo.environment,
            stdoutLog: root.appending(path: "stdout.log"),
            stderrLog: root.appending(path: "stderr.log")
        ))
        let result = try await executor.waitForExit(receipt.id)

        #expect(receipt.pid > 0)
        #expect(result.exitCode == 42)
        #expect(try String(contentsOf: result.stdoutLog, encoding: .utf8).contains("BOREAL_TEST_STARTED"))
        #expect(try String(contentsOf: result.stderrLog, encoding: .utf8).contains("BOREAL_TEST_DIAGNOSTIC"))
    }

    @Test func runtimeInstallationAndEnvironmentInitializationAreRealAndAtomic() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "boreal-runtime-test-\(UUID().uuidString)")
        let payload = root.appending(path: "payload/Wine Stable.app/Contents/Resources/wine/bin")
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try executable("#!/bin/sh\necho wine-11.14\n", at: payload.appending(path: "wine"))
        try executable("#!/bin/sh\nexit 0\n", at: payload.appending(path: "wineserver"))
        try executable("#!/bin/sh\nmkdir -p \"$WINEPREFIX/drive_c\" \"$WINEPREFIX/dosdevices\"\ntouch \"$WINEPREFIX/system.reg\" \"$WINEPREFIX/user.reg\"\nexit 0\n", at: payload.appending(path: "wineboot"))

        let archive = root.appending(path: "fake-runtime.tar.xz")
        let executor = SystemProcessExecutor()
        let tar = try await executor.launch(ProcessLaunchRequest(
            executable: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-cJf", archive.path, "-C", root.appending(path: "payload").path, "."],
            environment: ProcessInfo.processInfo.environment,
            stdoutLog: root.appending(path: "tar.stdout.log"),
            stderrLog: root.appending(path: "tar.stderr.log")
        ))
        let tarResult = try await executor.waitForExit(tar.id)
        #expect(tarResult.exitCode == 0)

        let manifest = BorealRuntime(
            schemaVersion: 1,
            id: "wine-11.14-boreal.test",
            displayName: "Boreal Runtime Test",
            wineVersion: "11.14",
            architecture: .x86_64,
            minimumMacOS: "15.0",
            channel: .stable,
            requirements: [],
            features: RuntimeFeatures(wow64: true, wineMono: false, wineGecko: false, d3dmetal: false, dxmt: false),
            artifact: RuntimeArtifact(url: archive, sha256: try RuntimeSecurity.sha256(of: archive), compressedSize: Int64((try Data(contentsOf: archive)).count))
        )
        let support = root.appending(path: "support")
        let runtimeManager = RuntimeManager(applicationSupportURL: support, catalog: StaticCatalog(runtimes: [manifest]), processExecutor: executor, requirementChecker: SatisfiedRequirements())
        let installed = try await runtimeManager.install(manifest)
        let validation = try await runtimeManager.validate(installed)

        #expect(validation.isReady)
        #expect(validation.detectedWineVersion == "wine-11.14")
        #expect(FileManager.default.fileExists(atPath: support.appending(path: "Runtimes/\(manifest.id)/installed-runtime.json").path))

        let environments = EnvironmentManager(applicationSupportURL: support, processExecutor: executor)
        let environment = try await environments.create(configuration: EnvironmentConfiguration(name: "Test App"), runtime: installed)
        try await environments.initialize(environment, runtime: installed)
        let environmentValidation = try await environments.validate(environment)
        #expect(environmentValidation.isReady)
        #expect(FileManager.default.fileExists(atPath: environment.prefixURL.appending(path: "drive_c").path))
        #expect(environment.prefixURL.path.hasPrefix(support.path))
    }

    private func executable(_ contents: String, at url: URL) throws {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

nonisolated private struct StaticCatalog: RuntimeCatalogLoading {
    let runtimes: [BorealRuntime]
    func loadCatalog() async throws -> [BorealRuntime] { runtimes }
}

nonisolated private struct SatisfiedRequirements: RuntimeRequirementChecking {
    func isSatisfied(_ requirement: RuntimeRequirement) async -> Bool { true }
}
