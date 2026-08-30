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
        let payloadRoot = root.appending(path: "payload")
        let payload = payloadRoot.appending(path: "Runtime/Wine.app/Contents/Resources/wine/bin")
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: payloadRoot.appending(path: "Dependencies"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: payloadRoot.appending(path: "Support"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: payloadRoot.appending(path: "Licenses"), withIntermediateDirectories: true)
        try Data("Test-only third-party notices".utf8).write(to: payloadRoot.appending(path: "Licenses/THIRD_PARTY_NOTICES.txt"))
        try Data("{\"spdxVersion\":\"SPDX-2.3\"}".utf8).write(to: payloadRoot.appending(path: "SBOM.spdx.json"))
        try executable("#!/bin/sh\necho wine-11.14\n", at: payload.appending(path: "wine"))
        try executable("#!/bin/sh\nexit 0\n", at: payload.appending(path: "wineserver"))
        try executable("#!/bin/sh\nmkdir -p \"$WINEPREFIX/drive_c\" \"$WINEPREFIX/dosdevices\"\ntouch \"$WINEPREFIX/system.reg\" \"$WINEPREFIX/user.reg\"\nexit 0\n", at: payload.appending(path: "wineboot"))

        let packageManifest = RuntimePackageManifest(
            schemaVersion: 1,
            id: "wine-11.14-boreal.test",
            displayName: "Boreal Runtime Test",
            wineVersion: "11.14",
            borealRevision: 1,
            architecture: .x86_64,
            minimumMacOS: "15.0",
            requiresRosetta: false,
            channel: .stable,
            features: RuntimeFeatures(wow64: true, wineMono: false, wineGecko: false, d3dmetal: false, dxmt: false),
            components: RuntimeComponents(),
            layout: .canonical
        )
        let packageEncoder = JSONEncoder()
        packageEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try packageEncoder.encode(packageManifest).write(to: payloadRoot.appending(path: "runtime.json"))

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
        #expect(FileManager.default.fileExists(atPath: support.appending(path: "Runtimes/\(manifest.id)/runtime.json").path))
        let permissions = try FileManager.default.attributesOfItem(atPath: installed.rootURL.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o555)

        let environments = EnvironmentManager(applicationSupportURL: support, processExecutor: executor)
        let environment = try await environments.create(configuration: EnvironmentConfiguration(name: "Test App"), runtime: installed)
        try await environments.initialize(environment, runtime: installed)
        let environmentValidation = try await environments.validate(environment)
        #expect(environmentValidation.isReady)
        #expect(FileManager.default.fileExists(atPath: environment.prefixURL.appending(path: "drive_c").path))
        #expect(environment.prefixURL.path.hasPrefix(support.path))

        try await runtimeManager.remove(installed)
        #expect(!FileManager.default.fileExists(atPath: installed.rootURL.path))
    }

    @Test func legacyRuntimeChannelsDecodeIntoVersionedChannels() throws {
        let developer = try JSONDecoder().decode(RuntimeChannel.self, from: Data("\"devel\"".utf8))
        let preview = try JSONDecoder().decode(RuntimeChannel.self, from: Data("\"staging\"".utf8))
        #expect(developer == .developer)
        #expect(preview == .preview)
    }

    @Test func localWineImportCreatesValidatedImmutableSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "boreal-local-runtime-\(UUID().uuidString)")
        let applications = root.appending(path: "Applications", directoryHint: .isDirectory)
        let sourceApp = applications.appending(path: "Wine Test.app", directoryHint: .isDirectory)
        let sourceBin = sourceApp.appending(path: "Contents/Resources/wine/bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceBin, withIntermediateDirectories: true)
        try executable("""
        #!/bin/sh
        case "${0##*/}" in
          wine) echo wine-11.15 ;;
          wineboot)
            mkdir -p "$WINEPREFIX/drive_c" "$WINEPREFIX/dosdevices"
            touch "$WINEPREFIX/system.reg" "$WINEPREFIX/user.reg"
            ;;
          *) exit 64 ;;
        esac
        """, at: sourceBin.appending(path: "wine"))
        try executable("#!/bin/sh\nexit 0\n", at: sourceBin.appending(path: "wineserver"))
        try FileManager.default.createSymbolicLink(atPath: sourceBin.appending(path: "wineboot").path, withDestinationPath: "wine")

        let candidate = LocalRuntimeCandidate(
            id: "local-wine-test-11-15-x86_64-r1",
            displayName: "Wine Test",
            wineVersion: "11.15",
            appURL: sourceApp,
            architecture: .x86_64,
            requirements: [],
            minimumMacOS: "15.0",
            estimatedSize: nil
        )
        let support = root.appending(path: "support", directoryHint: .isDirectory)
        let manager = RuntimeManager(
            applicationSupportURL: support,
            catalog: StaticCatalog(runtimes: []),
            processExecutor: SystemProcessExecutor(),
            requirementChecker: SatisfiedRequirements(),
            localApplicationRoots: [applications]
        )

        let installed = try await manager.importLocalRuntime(candidate)
        let validation = try await manager.validate(installed)
        #expect(installed.origin == .localImport)
        #expect(validation.isReady)
        #expect(FileManager.default.fileExists(atPath: sourceBin.appending(path: "wine").path))
        #expect(FileManager.default.fileExists(atPath: installed.rootURL.appending(path: "Licenses/THIRD_PARTY_NOTICES.txt").path))
        #expect(FileManager.default.fileExists(atPath: installed.rootURL.appending(path: "SBOM.spdx.json").path))
        let permissions = try FileManager.default.attributesOfItem(atPath: installed.rootURL.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o555)

        try await manager.remove(installed)
        #expect(!FileManager.default.fileExists(atPath: installed.rootURL.path))
    }

    @Test func localWineDiscoveryReadsCanonicalAppMetadataAndArchitecture() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "boreal-local-discovery-\(UUID().uuidString)")
        let applications = root.appending(path: "Applications", directoryHint: .isDirectory)
        let app = applications.appending(path: "Wine Discovery.app", directoryHint: .isDirectory)
        let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
        let bin = contents.appending(path: "Resources/wine/bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        for name in ["wine", "wineserver", "wineboot"] {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: bin.appending(path: name))
        }
        let info: [String: Any] = [
            "CFBundleName": "Wine Discovery",
            "CFBundleShortVersionString": "11.16",
            "LSMinimumSystemVersion": "15.0"
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appending(path: "Info.plist"))
        let manager = RuntimeManager(
            applicationSupportURL: root.appending(path: "support"),
            catalog: StaticCatalog(runtimes: []),
            processExecutor: SystemProcessExecutor(),
            requirementChecker: SatisfiedRequirements(),
            localApplicationRoots: [applications]
        )

        let candidates = await manager.localRuntimeCandidates()
        let candidate = try #require(candidates.first)
        #expect(candidates.count == 1)
        #expect(candidate.displayName == "Wine Discovery")
        #expect(candidate.wineVersion == "11.16")
        #expect(candidate.architecture == .arm64)
        #expect(candidate.appURL.resolvingSymlinksInPath() == app.resolvingSymlinksInPath())
    }

    @Test func localGPTKDiscoverySupportsBundledWine64WithoutNativeWineboot() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "boreal-gptk-discovery-\(UUID().uuidString)")
        let applications = root.appending(path: "Applications", directoryHint: .isDirectory)
        let app = applications.appending(path: "Game Porting Toolkit.app", directoryHint: .isDirectory)
        let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
        let bin = contents.appending(path: "Resources/wine/bin", directoryHint: .isDirectory)
        let d3dMetal = contents.appending(path: "Resources/wine/lib/external/D3DMetal.framework/Versions/A", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: d3dMetal, withIntermediateDirectories: true)
        for name in ["wine64", "wineserver"] {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: bin.appending(path: name))
        }
        try Data().write(to: d3dMetal.appending(path: "D3DMetal"))
        let info: [String: Any] = [
            "CFBundleName": "Game Porting Toolkit",
            "CFBundleShortVersionString": "3.0-2",
            "LSMinimumSystemVersion": "14.0"
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appending(path: "Info.plist"))
        let manager = RuntimeManager(
            applicationSupportURL: root.appending(path: "support"),
            catalog: StaticCatalog(runtimes: []),
            processExecutor: SystemProcessExecutor(),
            requirementChecker: SatisfiedRequirements(),
            localApplicationRoots: [applications]
        )

        let candidate = try #require(await manager.localRuntimeCandidates().first)
        #expect(candidate.displayName == "Game Porting Toolkit")
        #expect(candidate.wineVersion == "3.0-2")
        #expect(candidate.engine == .gamePortingToolkit)
        #expect(candidate.features.d3dmetal)
        #expect(candidate.layout.wineExecutable.hasSuffix("/wine64"))
        #expect(candidate.layout.wineBootExecutable == "Support/wineboot")
    }

    @Test func providerLaunchPlanCannotOverrideManagedPrefixOrRuntimePath() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "boreal-launch-plan-\(UUID().uuidString)")
        let runtimeBin = root.appending(path: "runtime/bin", directoryHint: .isDirectory)
        let workingDirectory = root.appending(path: "game", directoryHint: .isDirectory)
        let logs = root.appending(path: "environment/logs", directoryHint: .isDirectory)
        let prefix = root.appending(path: "environment/prefix", directoryHint: .isDirectory)
        let capture = root.appending(path: "captured.txt")
        try FileManager.default.createDirectory(at: runtimeBin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let wine = runtimeBin.appending(path: "wine")
        try executable("#!/bin/sh\nprintf '%s\\n' \"$WINEPREFIX\" \"$PATH\" \"$EPIC_ENV\" \"$PWD\" \"$@\" > \"\(capture.path)\"\n", at: wine)
        let game = workingDirectory.appending(path: "Game.exe")
        try Data().write(to: game)
        let runtime = InstalledRuntime(
            id: "runtime",
            displayName: "Runtime",
            wineVersion: "test",
            rootURL: root.appending(path: "runtime"),
            wineExecutable: wine,
            wineServerExecutable: runtimeBin.appending(path: "wineserver"),
            wineBootExecutable: runtimeBin.appending(path: "wineboot"),
            architecture: .arm64,
            requirements: []
        )
        let environment = ManagedBorealEnvironment(
            id: UUID(),
            configuration: EnvironmentConfiguration(name: "Game"),
            runtimeID: runtime.id,
            rootURL: root.appending(path: "environment"),
            prefixURL: prefix,
            logsURL: logs,
            state: .ready
        )
        let plan = WindowsLaunchPlan(
            executable: game,
            arguments: ["-windowed"],
            environment: ["WINEPREFIX": "/unsafe", "PATH": "/unsafe", "EPIC_ENV": "preserved"],
            workingDirectory: workingDirectory
        )
        let runner = WindowsProcessRunner(processExecutor: SystemProcessExecutor())
        let session = try await runner.run(plan: plan, environment: environment, runtime: runtime)
        let result = try await runner.waitForExit(session)
        #expect(result.exitCode == 0)
        let lines = try String(contentsOf: capture, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(lines[0] == prefix.path)
        #expect(lines[1].hasPrefix(runtimeBin.path + ":"))
        #expect(lines[2] == "preserved")
        #expect(URL(fileURLWithPath: lines[3]).resolvingSymlinksInPath() == workingDirectory.resolvingSymlinksInPath())
        #expect(lines[4] == game.path)
        #expect(lines[5] == "-windowed")
    }

    @Test func libraryProjectionSearchesMetadataAndCombinesFilterCategories() {
        let steam = StoreLibraryGame(
            provider: .steam,
            externalID: "10",
            name: "Żółta Przygoda",
            developer: "North Studio",
            playtimeMinutes: 180,
            lastPlayed: .now,
            isInstalled: true,
            compatibility: CommunityCompatibility(
                source: .protonDB,
                tier: .gold,
                reportCount: 12,
                fetchedAt: .now
            )
        )
        let epic = StoreLibraryGame(provider: .epic, externalID: "20", name: "Cloud Quest", isInstalled: false)
        let items = LibraryProjector.makeItems(applications: [], storeGames: [epic, steam])

        let result = LibraryProjector.project(
            items,
            searchText: "zolta north",
            sources: [.steam],
            availability: [.installed],
            compatibility: [.good],
            sort: .nameAscending
        )

        #expect(result.map(\.name) == ["Żółta Przygoda"])
    }

    @Test func libraryProjectionDoesNotDuplicateStoreGameLinkedToApplication() {
        let application = WindowsApplication(
            name: "BioShock",
            publisher: "2K",
            executablePath: "/tmp/bioshock.exe",
            installerPath: "/tmp/bioshock-installer.exe",
            environmentID: UUID(),
            storeProvider: .steam,
            storeExternalID: "7670"
        )
        let storeGame = StoreLibraryGame(provider: .steam, externalID: "7670", name: "BioShock")

        let items = LibraryProjector.makeItems(applications: [application], storeGames: [storeGame])

        #expect(items.count == 1)
        #expect(items.first?.name == "BioShock")
        #expect(items.first?.id == .application(application.id))
    }

    @Test func libraryProjectionSortsMissingActivityLastAndRecognizesAttention() {
        let environmentID = UUID()
        let healthy = WindowsApplication(
            name: "Later",
            publisher: "Boreal",
            executablePath: "/tmp/later.exe",
            installerPath: "/tmp/later-installer.exe",
            environmentID: environmentID,
            status: .ready,
            lastOpened: .now
        )
        let attention = WindowsApplication(
            name: "Attention",
            publisher: "Boreal",
            executablePath: "/tmp/attention.exe",
            installerPath: "/tmp/attention-installer.exe",
            environmentID: environmentID,
            status: .needsAttention
        )
        let items = LibraryProjector.makeItems(applications: [attention, healthy], storeGames: [])

        let sorted = LibraryProjector.project(
            items,
            searchText: "",
            sources: [],
            availability: [],
            compatibility: [],
            sort: .lastUsed
        )
        let filtered = LibraryProjector.project(
            items,
            searchText: "needs attention",
            sources: [],
            availability: [.needsAttention],
            compatibility: [],
            sort: .nameAscending
        )

        #expect(sorted.map(\.name) == ["Later", "Attention"])
        #expect(filtered.map(\.name) == ["Attention"])
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
