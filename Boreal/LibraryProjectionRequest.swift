import Foundation

struct LibraryProjectionRequest: Equatable {
    var searchText: String
    var sources: Set<LibrarySourceFilter>
    var availability: Set<LibraryAvailabilityFilter>
    var compatibility: Set<LibraryCompatibilityFilter>
    var sort: LibrarySort
    var producer: String
    var favorites: Set<String>
    var favoritesOnly: Bool
}

enum ConsoleLibraryScope: Equatable {
    case all, installed, recent, favorites
}
