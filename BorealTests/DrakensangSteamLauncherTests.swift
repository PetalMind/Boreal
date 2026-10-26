import Foundation
import Testing

@testable import Boreal

struct DrakensangSteamLauncherTests {
    @Test func preservesPlusCharactersInSteamTickets() {
        let ticket = Data([0xfb, 0xef, 0xff])
        let url = DrakensangPortal.loginURL(ticket: ticket)
        #expect(url.absoluteString.contains("%2B"))
        #expect(!url.absoluteString.contains("+"))
        #expect(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
                == ticket.base64EncodedString())
    }

    @Test func restrictsSignInToOfficialHTTPSDomains() {
        for value in ["https://steam.partner.drakensang.com/", "https://grimmag.drakensang.com/pl/play"] {
            #expect(DrakensangPortal.permits(URL(string: value)!))
        }
        for value in [
            "http://grimmag.drakensang.com/", "https://drakensang.com.attacker.example/",
            "https://evil-drakensang.com/", "https://steamcommunity.com/",
            "https://user@grimmag.drakensang.com/", "https://grimmag.drakensang.com:8443/",
        ] {
            #expect(!DrakensangPortal.permits(URL(string: value)!))
        }
    }

    @Test func parsesOfficialLaunchWithoutExecutingShellSyntax() throws {
        let html =
            #"<script>nebula3.launch('-sid "temporary-session" -root "https://grimmag.drakensang.com/" -language pl -standalone');</script>"#
        #expect(
            try DrakensangPortal.arguments(in: html) == [
                "-sid", "temporary-session", "-root", "https://grimmag.drakensang.com/", "-language", "pl",
                "-standalone",
            ])
        #expect(
            try DrakensangPortal.splitArguments(#"-name '$(touch /tmp/should-never-run)' `literal`"#) == [
                "-name", "$(touch /tmp/should-never-run)", "`literal`",
            ])
    }

    @Test func rejectsMissingOrMalformedSessionArguments() {
        for html in [
            "<html>Sign in</html>", #"nebula3.launch('-standalone');"#,
            #"nebula3.launch('-sid');"#, #"nebula3.launch('-sid "unfinished -standalone');"#,
            "nebula3.launch('-sid value\n-standalone');",
        ] {
            #expect(throws: DrakensangLaunchError.self) { try DrakensangPortal.arguments(in: html) }
        }
    }

    #if !DRAKENSANG_PORTAL_ONLY
        @Test func onlyRoutesDrakensangPlayToItsCompatibilityLauncher() {
            #expect(DrakensangSteamLauncher.applies(to: URL(string: "steam://rungameid/2067850")!))
            for value in ["steam://install/2067850", "steam://rungameid/3906660", "https://rungameid/2067850"] {
                #expect(!DrakensangSteamLauncher.applies(to: URL(string: value)!))
            }
        }
    #endif
}
