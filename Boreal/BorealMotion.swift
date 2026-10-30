import SwiftUI

enum BorealMotion {
    static let instant = Animation.easeOut(duration: 0.10)
    static let hover = Animation.easeOut(duration: 0.16)
    static let control = Animation.easeOut(duration: 0.20)
    static let stateChange = Animation.easeInOut(duration: 0.24)
    static let panel = Animation.easeInOut(duration: 0.28)
    static let navigation = Animation.spring(duration: 0.36, bounce: 0.06)
    static let hero = Animation.spring(duration: 0.46, bounce: 0.04)
    static let reorder = Animation.spring(duration: 0.30, bounce: 0.12)
}

struct BorealMotionEnvironment {
    let reduceMotion: Bool

    var instant: Animation? { reduceMotion ? .easeOut(duration: 0.08) : BorealMotion.instant }
    var hover: Animation? { reduceMotion ? .easeOut(duration: 0.08) : BorealMotion.hover }
    var control: Animation? { reduceMotion ? .easeOut(duration: 0.08) : BorealMotion.control }
    var stateChange: Animation? { reduceMotion ? .easeOut(duration: 0.08) : BorealMotion.stateChange }
    var panel: Animation? { reduceMotion ? .easeOut(duration: 0.12) : BorealMotion.panel }
    var navigation: Animation? { reduceMotion ? .easeOut(duration: 0.12) : BorealMotion.navigation }
    var hero: Animation? { reduceMotion ? .easeOut(duration: 0.14) : BorealMotion.hero }
    var reorder: Animation? { reduceMotion ? .easeOut(duration: 0.12) : BorealMotion.reorder }

    init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
    }
}
