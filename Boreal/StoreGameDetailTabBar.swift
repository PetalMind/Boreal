import SwiftUI

/// The same sections remain available when the detail pane becomes narrow.
struct StoreGameDetailTabBar<Tab: Hashable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> LocalizedStringResource

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                detailTabButtons
            }
            .fixedSize(horizontal: true, vertical: false)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 144), spacing: 4)], alignment: .leading, spacing: 4) {
                detailTabButtons
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var detailTabButtons: some View {
        ForEach(tabs, id: \.self) { tab in
            Button {
                selection = tab
            } label: {
                Text(title(tab))
                    .font(.callout.weight(selection == tab ? .semibold : .regular))
                    .foregroundStyle(selection == tab ? Color.accentColor : Color.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .frame(minWidth: 44, minHeight: 44)
                    .frame(maxWidth: .infinity)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor.opacity(0.12))
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if selection == tab {
                            Capsule().fill(Color.accentColor).frame(height: 3)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
        }
    }

}
