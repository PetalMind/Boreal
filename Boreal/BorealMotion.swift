import SwiftUI

/// Shared timing for pointer feedback, state changes and navigation.
enum BorealMotion {
    static let instant = Animation.smooth(duration: 0.12)
    static let hover = Animation.smooth(duration: 0.16)
    static let control = Animation.smooth(duration: 0.20)
    static let stateChange = Animation.smooth(duration: 0.24)
    static let panel = Animation.smooth(duration: 0.28)
    static let navigation = Animation.spring(duration: 0.32, bounce: 0)
    static let hero = Animation.spring(duration: 0.36, bounce: 0)
    static let reorder = Animation.spring(duration: 0.28, bounce: 0)
    static let scroll = Animation.smooth(duration: 0.24)
    static let inputDuration: TimeInterval = 0.06
    static let input = Animation.linear(duration: inputDuration)
    static let activity = Animation.easeInOut(duration: 1.2)
    static let progress = Animation.linear(duration: 0.16)
    static let reduced = Animation.easeOut(duration: 0.10)
}

struct BorealMotionEnvironment {
    let reduceMotion: Bool

    var instant: Animation? { reduceMotion ? nil : BorealMotion.instant }
    var hover: Animation? { reduceMotion ? nil : BorealMotion.hover }
    var control: Animation? { reduceMotion ? BorealMotion.reduced : BorealMotion.control }
    var stateChange: Animation? { reduceMotion ? BorealMotion.reduced : BorealMotion.stateChange }
    var panel: Animation? { reduceMotion ? BorealMotion.reduced : BorealMotion.panel }
    var navigation: Animation? { reduceMotion ? BorealMotion.reduced : BorealMotion.navigation }
    var hero: Animation? { reduceMotion ? BorealMotion.reduced : BorealMotion.hero }
    var reorder: Animation? { reduceMotion ? nil : BorealMotion.reorder }
    var scroll: Animation? { reduceMotion ? nil : BorealMotion.scroll }
    var input: Animation? { reduceMotion ? nil : BorealMotion.input }
    var progress: Animation? { reduceMotion ? nil : BorealMotion.progress }

    /// Reduced motion and disabled controls never change their geometry.
    func interactionScale(isHovered: Bool = false, isPressed: Bool = false, isEnabled: Bool = true) -> CGFloat {
        guard !reduceMotion, isEnabled else { return 1 }
        return isPressed ? 0.98 : (isHovered ? 1.01 : 1)
    }
}
