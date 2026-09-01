import Foundation
import Testing
@testable import Boreal

struct ExecutableDiscoveryTests {
    private let root = URL(fileURLWithPath: "/synthetic/drive_c", isDirectory: true)
    private let installStart = Date(timeIntervalSince1970: 1_000)

    @Test func ranksMainExecutableAheadOfMaintenanceAndSupportExecutables() {
        let before = snapshot([])
        let after = snapshot([
            entry("Program Files/Aurora/Aurora.exe", gui: true),
            entry("Program Files/Aurora/uninstall.exe", gui: true),
            entry("Program Files/Aurora/Aurora Updater.exe", gui: true),
            entry("Program Files/Aurora/AuroraHelper.exe", gui: true),
            entry("Program Files/Aurora/Crash Reporter.exe", gui: true),
            entry("Temp/setup.exe", gui: true),
            entry("Windows/System32/system-tool.exe", gui: true)
        ], capturedAt: installStart.addingTimeInterval(20))

        let candidates = ExecutableDiscovery.rankedCandidates(before: before, after: after, applicationName: "Aurora")

        #expect(candidates.first?.relativePath == "Program Files/Aurora/Aurora.exe")
        #expect(!candidates.map(\.relativePath).contains("Program Files/Aurora/uninstall.exe"))
        #expect(!candidates.map(\.relativePath).contains("Windows/System32/system-tool.exe"))
        #expect(candidates.map(\.relativePath).contains("Program Files/Aurora/Aurora Updater.exe"))
        #expect(candidates.first!.score > candidates.last!.score)
        #expect(candidates.dropFirst().allSatisfy { $0.score < ExecutableDiscovery.minimumLaunchCandidateScore })
    }

    @Test func ranksMatchingGUIInProgramFilesAheadOfOtherExecutables() {
        let before = snapshot([])
        let after = snapshot([
            entry("tools/Aurora.exe", gui: true, created: 1_018),
            entry("Program Files/Aurora/Worker.exe", gui: false, created: 1_019),
            entry("Program Files/Aurora/Aurora.exe", gui: true, created: 1_017),
            entry("Program Files/Other/Other.exe", gui: true, created: 1_020)
        ], capturedAt: installStart.addingTimeInterval(20))

        let candidates = ExecutableDiscovery.rankedCandidates(before: before, after: after, applicationName: "Aurora")

        #expect(candidates.first?.relativePath == "Program Files/Aurora/Aurora.exe")
        #expect(candidates.first?.isGUIExecutable == true)
        #expect(candidates[0].score > candidates[1].score)
    }

    @Test func ignoresUnchangedFilesFromBeforeSnapshotButIncludesReplacedOnes() {
        let unchanged = entry("Program Files/Shared/Legacy.exe", gui: true, created: 500, modified: 700, size: 100)
        let replacedBefore = entry("Program Files/Aurora/Aurora.exe", gui: true, created: 500, modified: 700, size: 100)
        let replacedAfter = entry("Program Files/Aurora/Aurora.exe", gui: true, created: 1_010, modified: 1_010, size: 200)
        let before = snapshot([unchanged, replacedBefore])
        let after = snapshot([unchanged, replacedAfter], capturedAt: installStart.addingTimeInterval(20))

        let candidates = ExecutableDiscovery.rankedCandidates(before: before, after: after, applicationName: "Aurora")

        #expect(candidates.map(\.relativePath) == ["Program Files/Aurora/Aurora.exe"])
    }

    @Test func creationDateBreaksOtherwiseEqualRanking() {
        let before = snapshot([])
        let after = snapshot([
            entry("Program Files/North/North Client.exe", gui: true, created: 1_005),
            entry("Program Files/South/South Client.exe", gui: true, created: 1_015)
        ], capturedAt: installStart.addingTimeInterval(20))

        let candidates = ExecutableDiscovery.rankedCandidates(before: before, after: after, applicationName: "Client")

        #expect(candidates.first?.relativePath == "Program Files/South/South Client.exe")
    }

    @Test func prefersProgramDataLauncherOverVendorSupportProcesses() {
        let before = snapshot([])
        let after = snapshot([
            entry("ProgramData/Lesta/GameCenter/lgc.exe", gui: true, created: 1_005),
            entry("ProgramData/Lesta/GameCenter/LestaErrorMonitor.exe", gui: true, created: 1_010),
            entry("ProgramData/Lesta/GameCenter/dlls/helper_process.exe", gui: true, created: 1_015),
            entry("ProgramData/Lesta/GameCenter/dlls/lgc_renderer_host.exe", gui: true, created: 1_020)
        ], capturedAt: installStart.addingTimeInterval(20))

        let candidates = ExecutableDiscovery.rankedCandidates(
            before: before,
            after: after,
            applicationName: "BASE.Installer.s-rq"
        )

        #expect(candidates.first?.relativePath == "ProgramData/Lesta/GameCenter/lgc.exe")
    }

    private func snapshot(
        _ entries: [ExecutableSnapshotEntry],
        capturedAt: Date? = nil
    ) -> ExecutableFilesystemSnapshot {
        ExecutableFilesystemSnapshot(rootURL: root, capturedAt: capturedAt ?? installStart, entries: entries)
    }

    private func entry(
        _ path: String,
        gui: Bool?,
        created: TimeInterval = 1_010,
        modified: TimeInterval = 1_010,
        size: Int64 = 1_024
    ) -> ExecutableSnapshotEntry {
        ExecutableSnapshotEntry(
            relativePath: path,
            creationDate: Date(timeIntervalSince1970: created),
            modificationDate: Date(timeIntervalSince1970: modified),
            fileSize: size,
            isGUIExecutable: gui
        )
    }
}
