import SwiftUI

struct SettingsCard<Content: View>: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let symbol: String
    let content: Content

    init(_ title: LocalizedStringResource, subtitle: LocalizedStringResource, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                heading.frame(width: 240, alignment: .leading)
                controls.frame(minWidth: 280)
            }
            VStack(alignment: .leading, spacing: 20) {
                heading
                controls
            }
        }
        .padding(20)
        .borealSurface()
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsRow<Content: View>: View {
    let title: LocalizedStringResource
    let content: Content

    init(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title).fixedSize()
                Spacer(minLength: 8)
                control
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                control
            }
        }
        .padding(.vertical, 8)
    }

    private var control: some View {
        content.accessibilityLabel(Text(title))
    }
}
