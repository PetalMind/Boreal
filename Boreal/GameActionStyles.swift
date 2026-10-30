import SwiftUI

enum GamePrimaryActionState: Equatable {
    case ready
    case preparing
    case starting
    case running
    case installing
    case failed
}

struct GamePrimaryActionButton: View {
    let title: String
    let symbol: String
    let state: GamePrimaryActionState
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: BorealMotionEnvironment {
        BorealMotionEnvironment(reduceMotion: reduceMotion)
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 156, alignment: .center)
        }
        .buttonStyle(BorealPrimaryActionButtonStyle())
        .animation(motion.control, value: state)
    }
}

struct BorealSecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(.cyan)
            .background(.blue.opacity(configuration.isPressed ? 0.28 : (isHovered ? 0.2 : 0.12)))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.blue.opacity(0.35))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : (isHovered ? 1.01 : 1))
            .onHover { isHovered = $0 }
            .animation(BorealMotionEnvironment(reduceMotion: reduceMotion).hover, value: isHovered)
            .animation(BorealMotionEnvironment(reduceMotion: reduceMotion).control, value: configuration.isPressed)
    }
}

struct BorealPrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .frame(minWidth: 132, minHeight: 40)
            .padding(.horizontal, 4)
            .background(
                LinearGradient(
                    colors: configuration.isPressed
                        ? [Color.blue.opacity(0.85), Color.blue.opacity(0.7)]
                        : [Color(red: 0.02, green: 0.58, blue: 1), Color.blue],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(color: .blue.opacity(0.28), radius: 8, y: 3)
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : (isHovered ? 1.01 : 1))
            .onHover { isHovered = $0 }
            .animation(BorealMotionEnvironment(reduceMotion: reduceMotion).hover, value: isHovered)
            .animation(BorealMotionEnvironment(reduceMotion: reduceMotion).control, value: configuration.isPressed)
    }
}

struct BorealSquareActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 40, height: 40)
            .background(.black.opacity(configuration.isPressed ? 0.50 : 0.34))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.white.opacity(0.14))
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(BorealMotionEnvironment(reduceMotion: reduceMotion).control, value: configuration.isPressed)
    }
}

struct BorealRailActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(configuration.role == .destructive ? Color.red : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .background(.white.opacity(isHovered && isEnabled ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6))
            .onHover { isHovered = $0 }
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.4)
    }
}

struct BorealDownloadProgressStyle: ProgressViewStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { proxy in
            let fraction = min(max(configuration.fractionCompleted ?? 0, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.10))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.cyan, .blue, .indigo],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, proxy.size.width * fraction))
                    .shadow(color: .cyan.opacity(0.35), radius: 6)
            }
        }
        .frame(height: 12)
        .animation(
            reduceMotion ? .linear(duration: 0.08) : .linear(duration: 0.15),
            value: configuration.fractionCompleted
        )
    }
}
