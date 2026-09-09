import Foundation

/// The language used by Boreal's own interface.
///
/// Regional formatting remains controlled by macOS. This preference only
/// selects the language used to resolve Boreal's String Catalog resources.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case polish

    var id: Self { self }

    var locale: Locale? {
        switch self {
        case .system:
            nil
        case .english:
            Locale(identifier: "en")
        case .polish:
            Locale(identifier: "pl")
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .system:
            .Settings.languageSystem
        case .english:
            .Settings.languageEnglish
        case .polish:
            .Settings.languagePolish
        }
    }
}
