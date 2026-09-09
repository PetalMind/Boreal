import Foundation

/// Locale inputs used by external services. This is deliberately separate from
/// `AppLanguage`: changing Boreal's UI language must not silently change price
/// country or the language requested from a storefront API.
nonisolated struct ExternalContentPreferences: Sendable {
    let steamLanguageCode: String
    let systemRegionCode: String

    static var system: Self {
        let locale = Locale.current
        return Self(
            steamLanguageCode: locale.language.languageCode?.identifier ?? "en",
            systemRegionCode: locale.region?.identifier ?? "PL"
        )
    }
}
