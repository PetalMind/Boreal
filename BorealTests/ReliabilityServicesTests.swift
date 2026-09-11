import Foundation
import Testing
@testable import Boreal

struct ReliabilityServicesTests {
    @Test func sanitizerRejectsBorealOwnedKeysAndPreservesRuntimeValues() {
        let result = EnvironmentVariableSanitizer.merge(
            base: ["WINEPREFIX": "/managed/prefix", "GAME_FLAG": "old"],
            custom: [
                CustomEnvironmentVariable(key: "GAME_FLAG", value: "new", enabled: true),
                CustomEnvironmentVariable(key: "WINEARCH", value: "win32", enabled: true),
                CustomEnvironmentVariable(key: "not-valid!", value: "x", enabled: true)
            ],
            borealOwned: ["WINEPREFIX": "/managed/prefix", "WINEARCH": "win64"]
        )

        #expect(result.values["GAME_FLAG"] == "new")
        #expect(result.values["WINEPREFIX"] == "/managed/prefix")
        #expect(result.values["WINEARCH"] == "win64")
        #expect(result.rejectedKeys.contains("WINEARCH"))
        #expect(result.rejectedKeys.contains("not-valid!"))
    }

    @Test func managedDLLOverrideWinsAndReportsManualConflict() {
        let result = DLLOverrideMerger.merge(
            managed: [DLLOverride(library: "d3d9", mode: .native)],
            manual: [DLLOverride(library: "D3D9", mode: .builtin)]
        )

        #expect(result.overrides == [DLLOverride(library: "d3d9", mode: .native)])
        #expect(result.warnings.count == 1)
    }

    @Test func dependencyAnalyzerUsesBinaryEvidenceWithoutLoadingDLLs() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "boreal-dependency-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appending(path: "game.exe")
        try syntheticPEWithImports().write(to: executable)

        let results = await DependencyAnalyzer().analyze(executable: executable)
        #expect(results.contains { $0.dependency == .vc2015To2022 && $0.confidence == .high })
        #expect(results.contains { $0.dependency == .xinput && $0.confidence == .high })
    }

    @Test func snapshotRestoresEnvironmentAndBlocksActiveSession() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "boreal-snapshot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let environmentRoot = root.appending(path: "Environment", directoryHint: .isDirectory)
        let environment = ManagedBorealEnvironment(
            id: UUID(),
            configuration: EnvironmentConfiguration(name: "Snapshot fixture"),
            runtimeID: "test-runtime",
            rootURL: environmentRoot,
            prefixURL: environmentRoot.appending(path: "prefix"),
            logsURL: environmentRoot.appending(path: "Logs"),
            state: .ready
        )
        try FileManager.default.createDirectory(at: environmentRoot, withIntermediateDirectories: true)
        try JSONEncoder().encode(environment).write(to: environmentRoot.appending(path: "environment.json"))
        let marker = environmentRoot.appending(path: "marker.txt")
        try Data("before".utf8).write(to: marker)

        let manager = EnvironmentSnapshotManager(snapshotsRootURL: root.appending(path: "Snapshots"))
        let snapshot = try await manager.createSnapshot(for: environment, reason: .manualCompatibilityChange)
        try Data("after".utf8).write(to: marker)

        let restored = try await manager.restore(snapshot, to: environment, activeSession: false)
        #expect(restored.state == .ready)
        #expect(String(data: try Data(contentsOf: marker), encoding: .utf8) == "before")
        #expect(await manager.snapshots(for: environment.id).isEmpty == false)
        await #expect(throws: SnapshotError.activeSession) {
            try await manager.restore(snapshot, to: environment, activeSession: true)
        }
    }

    private func syntheticPEWithImports() -> Data {
        var data = Data(repeating: 0, count: 0x400)
        data[0] = 0x4D
        data[1] = 0x5A
        putUInt32(0x80, into: &data, at: 0x3C)
        data[0x80] = 0x50
        data[0x81] = 0x45
        data[0x82] = 0
        data[0x83] = 0
        data[0x84] = 0x4C
        data[0x85] = 0x01
        data[0x86] = 0x01
        data[0x94] = 0xE0
        data[0x98] = 0x0B
        data[0x99] = 0x01
        putUInt32(2, into: &data, at: 0xF4)
        putUInt32(0x1000, into: &data, at: 0x100)
        putUInt32(0x40, into: &data, at: 0x104)

        let section = 0x178
        putUInt32(0x200, into: &data, at: section + 8)
        putUInt32(0x1000, into: &data, at: section + 12)
        putUInt32(0x200, into: &data, at: section + 16)
        putUInt32(0x200, into: &data, at: section + 20)

        putUInt32(0x1040, into: &data, at: 0x200)
        putUInt32(0x1050, into: &data, at: 0x20C)
        putUInt32(0x1040, into: &data, at: 0x210)
        putUInt32(0x1060, into: &data, at: 0x214)
        putUInt32(0x1068, into: &data, at: 0x220)
        putUInt32(0x1060, into: &data, at: 0x224)
        data.replaceSubrange(0x250..<0x250 + "vcruntime140_1.dll".utf8.count, with: "vcruntime140_1.dll".utf8)
        data[0x250 + "vcruntime140_1.dll".utf8.count] = 0
        data.replaceSubrange(0x268..<0x268 + "xinput1_3.dll".utf8.count, with: "xinput1_3.dll".utf8)
        data[0x268 + "xinput1_3.dll".utf8.count] = 0
        return data
    }

    private func putUInt32(_ value: UInt32, into data: inout Data, at offset: Int) {
        for index in 0..<4 {
            data[offset + index] = UInt8((value >> UInt32(index * 8)) & 0xFF)
        }
    }
}
