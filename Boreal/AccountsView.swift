import AppKit
import SwiftUI

struct AccountsView: View {
    @Environment(BorealStore.self) private var store
    @State private var showsAuthorizationCode = false
    @State private var authorizationCode = ""
    @State private var confirmsDisconnect = false
    @State private var showsGOGAuthorizationCode = false
    @State private var gogAuthorizationCode = ""
    @State private var confirmsGOGDisconnect = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Connect your game libraries")
                    .font(.largeTitle).fontWeight(.bold)
                Text("Boreal uses the providers’ own authorization flows. Passwords, CAPTCHA, and browser cookies never pass through Boreal.")
                    .foregroundStyle(.secondary)
                steamCard
                epicCard
                gogCard
            }
            .padding(34)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .task {
            store.refreshEpicConnection()
            store.refreshGOGConnection()
        }
        .onChange(of: store.epicConnectionState) { oldValue, newValue in
            if oldValue == .preparingSupport, newValue == .disconnected { beginEpicLogin() }
        }
        .onChange(of: store.gogConnectionState) { oldValue, newValue in
            if oldValue == .preparingSupport, newValue == .disconnected { beginGOGLogin() }
        }
        .sheet(isPresented: $showsAuthorizationCode) {
            VStack(alignment: .leading, spacing: 18) {
                Label("Finish Epic sign-in", systemImage: "person.badge.key.fill")
                    .font(.title2).fontWeight(.semibold)
                Text("After Epic signs you in, copy the authorizationCode value from the JSON page and paste it here. It is exchanged once by Legendary and is not saved by Boreal.")
                    .foregroundStyle(.secondary)
                TextEditor(text: $authorizationCode)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Button("Cancel", role: .cancel) { showsAuthorizationCode = false; authorizationCode = "" }
                    Spacer()
                    Button("Connect", systemImage: "link") {
                        showsAuthorizationCode = false
                        store.connectEpic(authorizationCode: authorizationCode)
                        authorizationCode = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(authorizationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(26)
            .frame(width: 520)
        }
        .confirmationDialog("Disconnect Epic Games?", isPresented: $confirmsDisconnect) {
            Button("Disconnect", role: .destructive) { store.disconnectEpic() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Boreal will delete Legendary’s local Epic credentials and remove Epic titles from this Library. Downloaded game files are kept.")
        }
        .sheet(isPresented: $showsGOGAuthorizationCode) {
            VStack(alignment: .leading, spacing: 18) {
                Label("Finish GOG sign-in", systemImage: "person.badge.key.fill")
                    .font(.title2).fontWeight(.semibold)
                Text("After GOG signs you in, copy the final page URL or its code value and paste it here. Boreal gives the one-time code directly to heroic-gogdl; your password and browser session remain with GOG.")
                    .foregroundStyle(.secondary)
                TextEditor(text: $gogAuthorizationCode)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Button("Cancel", role: .cancel) { showsGOGAuthorizationCode = false; gogAuthorizationCode = "" }
                    Spacer()
                    Button("Connect", systemImage: "link") {
                        showsGOGAuthorizationCode = false
                        store.connectGOG(authorizationCode: gogAuthorizationCode)
                        gogAuthorizationCode = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(gogAuthorizationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(26)
            .frame(width: 540)
        }
        .confirmationDialog("Disconnect GOG?", isPresented: $confirmsGOGDisconnect) {
            Button("Disconnect", role: .destructive) { store.disconnectGOG() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Boreal will delete heroic-gogdl’s local GOG tokens and remove GOG titles from this Library. Downloaded game files are kept.")
        }
    }

    private var steamCard: some View {
        accountCard(symbol: "gamecontroller.fill", title: "Steam", tint: .blue) {
            Label("Uses the account signed in to the Steam app", systemImage: "checkmark.shield.fill")
                .foregroundStyle(.secondary)
            HStack {
                Button("Open Steam to sign in", systemImage: "person.crop.circle.badge.plus") { openSteamSignIn() }
                Button("Refresh Steam Library", systemImage: "arrow.clockwise") { store.syncSteamLibrary() }
                    .disabled(store.librarySyncState == .syncing(.steam))
            }
        }
    }

    private var epicCard: some View {
        accountCard(symbol: "e.square.fill", title: "Epic Games", tint: .indigo) {
            switch store.epicConnectionState {
            case .checking:
                statusRow("Checking Epic support…")
            case .supportNotInstalled:
                Text("Install the verified Legendary 0.21.0 helper to connect, import, and manage your Epic library.")
                    .foregroundStyle(.secondary)
                Button("Install Epic Support and Sign In", systemImage: "arrow.down.circle") { store.prepareEpicSupport() }
                    .buttonStyle(.borderedProminent)
            case .disconnected:
                Text("Epic support is installed. Sign in through Epic’s website with a one-time authorization code.")
                    .foregroundStyle(.secondary)
                Button("Sign In to Epic Games", systemImage: "person.crop.circle.badge.plus") { beginEpicLogin() }
                    .buttonStyle(.borderedProminent)
            case .preparingSupport:
                statusRow("Downloading and verifying Epic support…")
            case .authenticating:
                statusRow("Connecting your Epic account…")
            case .connected(let displayName):
                Label(displayName ?? "Epic account connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                HStack {
                    Button("Refresh Library", systemImage: "arrow.clockwise") { store.syncEpicLibrary() }
                        .disabled(store.librarySyncState == .syncing(.epic))
                    Button("Disconnect…", role: .destructive) { confirmsDisconnect = true }
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                HStack {
                    Button("Check Again", systemImage: "arrow.clockwise") { store.refreshEpicConnection() }
                    Button("Open Sign-in", systemImage: "safari") { beginEpicLogin() }
                }
            }
            Link("Legendary source and GPL-3.0 license", destination: URL(string: "https://github.com/legendary-gl/legendary")!)
                .font(.caption)
        }
    }

    private var gogCard: some View {
        accountCard(symbol: "g.square.fill", title: "GOG", tint: .purple) {
            switch store.gogConnectionState {
            case .checking:
                statusRow("Checking GOG support…")
            case .supportNotInstalled:
                Text("Install the verified heroic-gogdl 1.3.0 helper to connect, import, install, and run your GOG Windows library.")
                    .foregroundStyle(.secondary)
                Button("Install GOG Support and Sign In", systemImage: "arrow.down.circle") { store.prepareGOGSupport() }
                    .buttonStyle(.borderedProminent)
            case .disconnected:
                Text("GOG support is installed. Sign in on GOG’s website and return the one-time authorization code.")
                    .foregroundStyle(.secondary)
                Button("Sign In to GOG", systemImage: "person.crop.circle.badge.plus") { beginGOGLogin() }
                    .buttonStyle(.borderedProminent)
            case .preparingSupport:
                statusRow("Downloading and verifying GOG support…")
            case .authenticating:
                statusRow("Connecting your GOG account…")
            case .connected(let displayName):
                Label(displayName ?? "GOG account connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                HStack {
                    Button("Refresh Library", systemImage: "arrow.clockwise") { store.syncGOGLibrary() }
                        .disabled(store.librarySyncState == .syncing(.gog))
                    Button("Disconnect…", role: .destructive) { confirmsGOGDisconnect = true }
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                HStack {
                    Button("Check Again", systemImage: "arrow.clockwise") { store.refreshGOGConnection() }
                    Button("Open Sign-in", systemImage: "safari") { beginGOGLogin() }
                }
            }
            Link("heroic-gogdl source and GPL-3.0 license", destination: URL(string: "https://github.com/Heroic-Games-Launcher/heroic-gogdl")!)
                .font(.caption)
        }
    }

    private func accountCard<Content: View>(symbol: String, title: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.title2).fontWeight(.semibold)
                content()
            }
            Spacer()
        }
        .padding(22)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.15)) }
    }

    private func statusRow(_ text: String) -> some View {
        HStack(spacing: 9) { ProgressView().controlSize(.small); Text(text).foregroundStyle(.secondary) }
    }

    private func beginEpicLogin() {
        guard let url = URL(string: "https://legendary.gl/epiclogin") else { return }
        NSWorkspace.shared.open(url)
        showsAuthorizationCode = true
    }

    private func beginGOGLogin() {
        let value = "https://auth.gog.com/auth?client_id=46899977096215655&redirect_uri=https%3A%2F%2Fembed.gog.com%2Fon_login_success%3Forigin%3Dclient&response_type=code&layout=client2"
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
        showsGOGAuthorizationCode = true
    }

    private func openSteamSignIn() {
        guard let url = URL(string: "steam://openmain") else { return }
        NSWorkspace.shared.open(url)
    }
}
