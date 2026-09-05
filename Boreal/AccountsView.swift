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
        GeometryReader { geometry in
            ScrollView {
                if geometry.size.width >= 1080 {
                    HStack(alignment: .top, spacing: 32) {
                        accountsContent.frame(maxWidth: .infinity)
                        informationPanel.frame(width: 310)
                    }
                    .padding(32)
                } else {
                    VStack(alignment: .leading, spacing: 28) {
                        accountsContent
                        informationPanel
                    }
                    .padding(28)
                }
            }
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

    @State private var showsHelp = false
    @State private var showsOtherStores = false

    private var accountsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ACCOUNTS").font(.caption.weight(.medium)).tracking(1.3).foregroundStyle(.secondary)
            HStack {
                Text("Connect your game libraries").font(.system(size: 30, weight: .bold))
                Spacer()
                Button("Learn more", systemImage: "book") { showsHelp = true }
                    .controlSize(.large)
            }
            Text("Link your accounts to import your games and keep them in sync.")
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
            steamCard
            gogCard
            epicCard
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { otherStoresCard; manualGameCard }
                VStack(spacing: 12) { otherStoresCard; manualGameCard }
            }
            .padding(.top, 8)
        }
        .sheet(isPresented: $showsHelp) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Connecting your libraries").font(.title2.bold())
                Text("Steam uses the account signed in to the Steam app. For GOG and Epic, choose Connect and complete sign-in in your browser, then paste the one-time code into Boreal.")
                Text("Use Manage to refresh or disconnect an account. Automatic sync refreshes enabled libraries every 8 hours while Boreal is running, or after the next launch when overdue.")
                Text("Passwords and browser cookies stay with the provider. Local authorization credentials are managed by the store helpers.")
                    .foregroundStyle(.secondary)
                Link("Epic helper documentation", destination: URL(string: "https://github.com/legendary-gl/legendary")!)
                Link("GOG helper documentation", destination: URL(string: "https://github.com/Heroic-Games-Launcher/heroic-gogdl")!)
                Button("Done") { showsHelp = false }.frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(28).frame(width: 520)
        }
        .sheet(isPresented: $showsOtherStores) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Other stores & launchers").font(.title2.bold())
                Text("Battle.net, Ubisoft Connect and EA app do not have direct account integration in Boreal. You can import a Windows installer and run it in a compatible environment.")
                Button("Choose Windows installer…") {
                    showsOtherStores = false
                    NotificationCenter.default.post(name: .installWindowsApp, object: nil)
                }
                .buttonStyle(.borderedProminent)
                Button("Done") { showsOtherStores = false }
            }
            .padding(28).frame(width: 480)
        }
    }

    private var steamCard: some View {
        accountCard(provider: .steam, logo: "SteamLogo", title: "Steam",
                    subtitle: "Import your Steam library. Install and play through Steam.") {
            Text(store.storeGames.contains(where: { $0.provider == .steam }) ? "Library imported · Sign-in managed by Steam" : "Sign in using the Steam app")
                .foregroundStyle(.secondary)
        } actions: {
            Menu("Manage") {
                Button("Open Steam to sign in") { openSteamSignIn() }
                Button("Refresh Library") { store.syncSteamLibrary() }
                    .disabled(isSyncing)
            }
        }
    }

    private var epicCard: some View {
        accountCard(provider: .epic, logo: "EpicGamesLogo", title: "Epic Games Store",
                    subtitle: "Sync your Epic library, including free games.") {
            switch store.epicConnectionState {
            case .checking: statusRow("Checking account…")
            case .preparingSupport: statusRow("Preparing Epic support…")
            case .authenticating: statusRow("Connecting account…")
            case .connected(let name): connectedStatus(name)
            case .failed(let message): Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            default: disconnectedStatus
            }
        } actions: {
            switch store.epicConnectionState {
            case .connected:
                Menu("Manage") {
                    Button("Refresh Library") { store.syncEpicLibrary() }.disabled(isSyncing)
                    Button("Disconnect…", role: .destructive) { confirmsDisconnect = true }
                }
            case .failed:
                Menu("Try again") {
                    Button("Check Again") { store.refreshEpicConnection() }
                    Button("Open Sign-in") { beginEpicLogin() }
                }
            default:
                Button("Connect") {
                    if store.epicConnectionState == .supportNotInstalled { store.prepareEpicSupport() }
                    else { beginEpicLogin() }
                }
                .buttonStyle(.borderedProminent).disabled(store.epicConnectionState.isBusy)
            }
        }
    }

    private var gogCard: some View {
        accountCard(provider: .gog, logo: "GOGLogo", title: "GOG.com",
                    subtitle: "Import your DRM-free games from GOG.") {
            switch store.gogConnectionState {
            case .checking: statusRow("Checking account…")
            case .preparingSupport: statusRow("Preparing GOG support…")
            case .authenticating: statusRow("Connecting account…")
            case .connected(let name): connectedStatus(name)
            case .failed(let message): Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            default: disconnectedStatus
            }
        } actions: {
            switch store.gogConnectionState {
            case .connected:
                Menu("Manage") {
                    Button("Refresh Library") { store.syncGOGLibrary() }.disabled(isSyncing)
                    Button("Disconnect…", role: .destructive) { confirmsGOGDisconnect = true }
                }
            case .failed:
                Menu("Try again") {
                    Button("Check Again") { store.refreshGOGConnection() }
                    Button("Open Sign-in") { beginGOGLogin() }
                }
            default:
                Button("Connect") {
                    if store.gogConnectionState == .supportNotInstalled { store.prepareGOGSupport() }
                    else { beginGOGLogin() }
                }
                .buttonStyle(.borderedProminent).disabled(store.gogConnectionState.isBusy)
            }
        }
    }

    private var isSyncing: Bool {
        if case .syncing = store.librarySyncState { return true }
        return false
    }

    private var disconnectedStatus: some View {
        Label("Not connected", systemImage: "circle.fill")
            .font(.caption).foregroundStyle(.secondary)
    }

    private func connectedStatus(_ name: String?) -> some View {
        HStack(spacing: 8) {
            Label("Connected", systemImage: "circle.fill").foregroundStyle(.green)
            if let name { Text(name).foregroundStyle(.secondary) }
        }
        .font(.caption)
    }

    private func accountCard<Status: View, Actions: View>(
        provider: GameLibraryProvider, logo: String, title: String, subtitle: String,
        @ViewBuilder status: () -> Status, @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 18) {
                Image(logo).resizable().scaledToFit().padding(10)
                    .frame(width: 66, height: 66)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 15))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    status()
                }
                Spacer(minLength: 0)
                actions().controlSize(.large).fixedSize()
            }
            HStack {
                if store.librarySyncState == .syncing(provider) {
                    statusRow("Syncing library…")
                } else if case .failed(let source, let message) = store.librarySyncState, source == provider {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else {
                    Label("\(store.storeGames.filter { $0.provider == provider }.count.formatted()) games imported", systemImage: "gamecontroller")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                AccountSyncToggle(provider: provider)
            }
            .font(.caption)
        }
        .padding(20)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.09)) }
    }

    private var otherStoresCard: some View {
        actionCard("Other Stores & Launchers", detail: "Battle.net, Ubisoft Connect, EA app and more.", symbol: "link", button: "See Options") {
            showsOtherStores = true
        }
    }

    private var manualGameCard: some View {
        actionCard("Add Game Manually", detail: "Install a game from a Windows installer.", symbol: "folder.badge.plus", button: "Add Game") {
            NotificationCenter.default.post(name: .installWindowsApp, object: nil)
        }
    }

    private func actionCard(_ title: String, detail: String, symbol: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title2).frame(width: 42, height: 46)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(button, action: action).controlSize(.large).fixedSize()
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 66)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.09)) }
    }

    private var informationPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    LinearGradient(colors: [.indigo.opacity(0.4), .cyan.opacity(0.12), .clear], startPoint: .topTrailing, endPoint: .bottomLeading)
                    if store.storeGames.isEmpty {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 64)).foregroundStyle(.white.opacity(0.6))
                    } else {
                        HStack(spacing: 10) {
                            ForEach(Array(store.storeGames.prefix(3))) { game in
                                GameArtworkView(game: game, width: 92, height: 138)
                                    .rotationEffect(.degrees(-12))
                            }
                        }
                    }
                }
                .frame(height: 164).clipped().accessibilityHidden(true)
                Text("All your games in one place").font(.title2.weight(.semibold))
                Text("Connect your stores to build a unified library, manage installations and launch your games with Boreal.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
            feature("Automatic sync", detail: "Keep your library up to date every 8 hours.", symbol: "arrow.triangle.2.circlepath")
            feature("Import game details", detail: "Covers, descriptions and store links.", symbol: "list.bullet")
            feature("Install and play", detail: "Use Wine, GPTK or native macOS where supported.", symbol: "play")
            feature("Local credentials", detail: "Sign in with your provider. Store helpers keep authorization on this Mac.", symbol: "lock")
            VStack(alignment: .leading, spacing: 10) {
                Label("Questions?", systemImage: "questionmark.circle").fontWeight(.semibold)
                Text("Find setup guidance and provider documentation.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open connection guide ↗") { showsHelp = true }.buttonStyle(.link)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.1)) }
        }
    }

    private func feature(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2)
                .frame(width: 46, height: 46)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).fontWeight(.semibold)
                Text(detail).foregroundStyle(.secondary).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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


private struct AccountSyncToggle: View {
    @AppStorage private var isEnabled: Bool

    init(provider: GameLibraryProvider) {
        _isEnabled = AppStorage(wrappedValue: true, "automaticLibrarySync." + provider.rawValue)
    }

    var body: some View {
        Toggle("Sync automatically", isOn: $isEnabled)
            .toggleStyle(.switch).controlSize(.mini).fixedSize()
            .help("Refresh this library every 8 hours while Boreal is running.")
    }
}
