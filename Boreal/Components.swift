import SwiftUI

struct AppIconView: View {
    let symbol: String
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.55, blue: 0.72), Color(red: 0.20, green: 0.30, blue: 0.56)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
        .accessibilityHidden(true)
    }
}

struct CompatibilityLabel: View {
    let rating: CompatibilityRating
    var body: some View { Label(rating.rawValue, systemImage: rating.symbol).foregroundStyle(color) }
    private var color: Color {
        switch rating {
        case .excellent: .green
        case .good: .teal
        case .limited: .orange
        case .unknown: .secondary
        case .unsupported: .red
        }
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    var symbol: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value)
            }
            Spacer()
        }
        .padding(.vertical, 5)
    }
}

struct BorealEmptyState: View {
    let action: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Boreal", systemImage: "sparkles.rectangle.stack")
        } description: {
            VStack(spacing: 6) {
                Text("Windows apps. At home on your Mac.")
                Text("Install an app to get started.")
            }
        } actions: {
            Button("Install App", systemImage: "plus", action: action).buttonStyle(.borderedProminent).controlSize(.large)
            Text("You can also drop an .exe or .msi file here").font(.caption).foregroundStyle(.secondary)
        }
    }
}

