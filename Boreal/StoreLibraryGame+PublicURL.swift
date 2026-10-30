import Foundation

extension StoreLibraryGame {
    /// Only publish a link when the provider gives us a stable public identity.
    var discordStorePageURL: String? {
        guard provider == .steam, externalID.utf8.allSatisfy({ (48...57).contains($0) }), !externalID.isEmpty else { return nil }
        return "https://store.steampowered.com/app/\(externalID)/"
    }
}
