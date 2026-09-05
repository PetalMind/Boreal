import AVFAudio
import Foundation

enum BorealSoundSettings {
    static let enabled = "interfaceSoundsEnabled"
    static let volume = "interfaceSoundVolume"
    static let completedDownloads = "interfaceSoundsCompletedDownloads"
    static let installations = "interfaceSoundsInstallations"
    static let errorsAndWarnings = "interfaceSoundsErrorsAndWarnings"
}

@MainActor
final class SoundService {
    static let shared = SoundService()

    enum Event: String {
        case confirmation = "boreal-confirmation"
        case installationStarted = "boreal-task-start"
        case installationCompleted = "boreal-success"
        case downloadCompleted = "boreal-task-complete"
        case launch = "boreal-launch"
        case warning = "boreal-warning"
        case error = "boreal-error"

        fileprivate var gain: Float {
            switch self {
            case .confirmation: 0.24
            case .installationStarted: 0.20
            case .installationCompleted: 0.22
            case .downloadCompleted: 0.20
            case .launch: 0.18
            case .warning: 0.22
            case .error: 0.24
            }
        }
    }

    private var players: [AVAudioPlayer] = []

    private init() {}

    func play(_ event: Event) {
        guard isEnabled(for: event),
              let url = Bundle.main.url(forResource: event.rawValue, withExtension: "wav", subdirectory: "Sounds")
                    ?? Bundle.main.url(forResource: event.rawValue, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }

        players.removeAll { !$0.isPlaying }
        player.volume = volume * event.gain
        player.prepareToPlay()
        players.append(player)
        player.play()
    }

    private func isEnabled(for event: Event) -> Bool {
        guard UserDefaults.standard.object(forKey: BorealSoundSettings.enabled) as? Bool ?? true else { return false }
        switch event {
        case .confirmation: return true
        case .installationStarted, .installationCompleted, .launch:
            return UserDefaults.standard.object(forKey: BorealSoundSettings.installations) as? Bool ?? true
        case .downloadCompleted:
            return UserDefaults.standard.object(forKey: BorealSoundSettings.completedDownloads) as? Bool ?? true
        case .warning, .error:
            return UserDefaults.standard.object(forKey: BorealSoundSettings.errorsAndWarnings) as? Bool ?? true
        }
    }

    private var volume: Float {
        let stored = UserDefaults.standard.object(forKey: BorealSoundSettings.volume) as? Double ?? 0.35
        return Float(min(max(stored, 0), 1))
    }
}
