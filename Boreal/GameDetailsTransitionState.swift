import Foundation

enum GameDetailsTransitionPhase: Equatable {
    case library
    case opening
    case details
    case closing
}

struct GameDetailsTransitionState: Equatable {
    var selectedGameID: UUID?
    var phase: GameDetailsTransitionPhase = .library
    var usesArtworkTransition = false

    static let library = Self(selectedGameID: nil, phase: .library)
}
