import SwiftUI

struct DiscordSettingsView: View {
    @AppStorage(DiscordPresence.enabledKey) private var enabled = false
    @AppStorage(DiscordPresence.applicationIDKey) private var applicationID = ""
    private var presence: DiscordPresence { .shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SettingsCard("Discord Rich Presence", subtitle: "Share your running game and session time with Discord.", symbol: "gamecontroller") {
                    Toggle("Show the running game in Discord", isOn: $enabled)
                        .padding(.bottom, 16)
                    Text("Application ID").font(.headline)
                    TextField("Discord Application ID", text: $applicationID)
                        .textFieldStyle(.roundedBorder)
                        .padding(.vertical, 8)
                    Text("Create an application in the Discord Developer Portal and paste its Application ID here. No login or user token is needed. The Discord desktop app must be running.")
                        .font(.callout).foregroundStyle(.secondary)
                    Link("Open Discord Developer Portal", destination: URL(string: "https://discord.com/developers/applications")!)
                        .padding(.top, 10)
                    Divider().padding(.vertical, 16)
                    Text(presence.status).font(.callout).foregroundStyle(.secondary)
                    Text("Only the game title, public cover and session start time are shared. Installers and the Steam launcher are excluded. When several games are running, Boreal shares the most recently launched game.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
            }
            .padding(32)
        }
        .onChange(of: enabled) { presence.settingsChanged() }
        .onChange(of: applicationID) { presence.settingsChanged() }
        .onAppear { presence.start() }
    }
}
