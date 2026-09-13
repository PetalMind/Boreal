import Foundation
import XCTest
@testable import Boreal

final class ModManagerWineIntegrationTests: XCTestCase {
    /// Read-only integration check for a real Skyrim Wine prefix.
    ///
    /// Configure BOREAL_WINE_PREFIX and BOREAL_SKYRIM_ROOT in the test
    /// scheme when a real Skyrim SE installation is available. The test never
    /// writes to the prefix or to plugins.txt.
    func testLoadsPluginsFromRealWinePrefix() throws {
        guard let prefixPath = ProcessInfo.processInfo.environment["BOREAL_WINE_PREFIX"],
              !prefixPath.isEmpty,
              let gameRootPath = ProcessInfo.processInfo.environment["BOREAL_SKYRIM_ROOT"],
              !gameRootPath.isEmpty else {
            throw XCTSkip("Set BOREAL_WINE_PREFIX and BOREAL_SKYRIM_ROOT for the real-prefix integration check.")
        }

        let prefix = URL(fileURLWithPath: prefixPath, isDirectory: true)
        let gameRoot = URL(fileURLWithPath: gameRootPath, isDirectory: true)
        let pluginsFile = try XCTUnwrap(SkyrimModAdapter.pluginsFile(in: prefix))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pluginsFile.path))
        XCTAssertNotNil(SkyrimModAdapter.dataRoot(for: gameRoot))

        let support = FileManager.default.temporaryDirectory
            .appending(path: "boreal-mod-integration-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: support) }

        let state = try ModManager(applicationSupportURL: support).load(
            gameID: UUID(),
            gameRoot: gameRoot,
            pluginsFile: pluginsFile
        )

        XCTAssertFalse(state.plugins.isEmpty, "The real Skyrim prefix should expose at least one plugin.")
        XCTAssertTrue(
            state.plugins.allSatisfy(\.headerParsed),
            "Every plugin visible in the real prefix must have a readable TES4 header."
        )
    }
}
