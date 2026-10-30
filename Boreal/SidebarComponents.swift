import SwiftUI

struct BorealSidebarSectionHeader: View {
    let title: LocalizedStringResource

    init(_ title: LocalizedStringResource) { self.title = title }

    var body: some View {
        Text(title)
            .textCase(.uppercase)
            .font(.caption2.weight(.bold))
            .tracking(1.15)
            .foregroundStyle(.secondary)
    }
}

struct BorealSidebarRow: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let symbol: String
    let tint: Color
    var count: Int?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(isSelected ? .semibold : .medium))
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer(minLength: 4)
            if let count {
                Text(count.formatted())
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(isSelected ? tint : Color(nsColor: .tertiaryLabelColor))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

}

struct BorealStoreSidebarRow: View {
    let source: LibrarySourceFilter
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            BorealStoreMark(source: source, isSelected: isSelected)

            VStack(alignment: .leading, spacing: 1) {
                Text(source.title)
                    .font(.callout.weight(isSelected ? .semibold : .medium))
                Text(source.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
            Text(count.formatted())
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(isSelected ? source.brandColor : Color(nsColor: .tertiaryLabelColor))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct BorealStoreMark: View {
    let source: LibrarySourceFilter
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(source.brandGradient)
            if let assetName = source.brandAssetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .padding(source == .epic ? 5 : 6)
            } else {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 30, height: 30)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(isSelected ? 0.28 : 0.12), lineWidth: 0.75)
        }
        .shadow(color: source.brandColor.opacity(isSelected ? 0.28 : 0.10), radius: 4, y: 2)
        .accessibilityHidden(true)
    }
}

extension LibrarySourceFilter {
    var subtitle: String {
        switch self {
        case .boreal: "Your locally installed games"
        case .steam: "Steam library"
        case .epic: "Epic collection"
        case .gog: "DRM-free games"
        }
    }

    var brandAssetName: String? {
        switch self {
        case .boreal: nil
        case .steam: "SteamLogo"
        case .epic: "EpicGamesLogo"
        case .gog: "GOGLogo"
        }
    }

    var brandColor: Color {
        switch self {
        case .boreal: .cyan
        case .steam: Color(red: 0.12, green: 0.53, blue: 0.78)
        case .epic: Color(red: 0.42, green: 0.43, blue: 0.47)
        case .gog: Color(red: 0.60, green: 0.29, blue: 0.82)
        }
    }

    var brandGradient: LinearGradient {
        switch self {
        case .boreal:
            LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .steam:
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.18, blue: 0.29), Color(red: 0.10, green: 0.55, blue: 0.78)], startPoint: .topLeading,
                endPoint: .bottomTrailing)
        case .epic:
            LinearGradient(colors: [Color(red: 0.18, green: 0.18, blue: 0.20), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .gog:
            LinearGradient(
                colors: [Color(red: 0.39, green: 0.18, blue: 0.56), Color(red: 0.74, green: 0.32, blue: 0.77)], startPoint: .topLeading,
                endPoint: .bottomTrailing)
        }
    }
}
