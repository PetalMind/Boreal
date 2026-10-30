import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, downloads, storage, runtime, controllers, fullscreen, overlay, integrations, advanced

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .general: .Settings.generalTitle
        case .downloads: .Settings.downloadsTitle
        case .storage: .Settings.storageTitle
        case .runtime: .Settings.runtimeTitle
        case .controllers: .Settings.controllersTitle
        case .fullscreen: .Settings.fullscreenTitle
        case .overlay: .Settings.overlayTitle
        case .integrations: "Integrations"
        case .advanced: .Settings.advancedTitle
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .general: .Settings.generalSubtitle
        case .downloads: .Settings.downloadsSubtitle
        case .storage: .Settings.storageSubtitle
        case .runtime: .Settings.runtimeSubtitle
        case .controllers: .Settings.controllersSubtitle
        case .fullscreen: .Settings.fullscreenSubtitle
        case .overlay: .Settings.overlaySubtitle
        case .integrations: "Discord Rich Presence"
        case .advanced: .Settings.advancedSubtitle
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .downloads: "arrow.down.circle.fill"
        case .storage: "internaldrive.fill"
        case .runtime: "gearshape.2.fill"
        case .controllers: "gamecontroller.fill"
        case .fullscreen: "rectangle.inset.filled"
        case .overlay: "gauge.with.dots.needle.67percent"
        case .integrations: "link"
        case .advanced: "wrench.and.screwdriver.fill"
        }
    }
}
