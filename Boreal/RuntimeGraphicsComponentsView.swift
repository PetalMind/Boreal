import SwiftUI

struct RuntimeGraphicsComponentsView: View {
    let components: [InstalledGraphicsComponent]

    var body: some View {
        if !components.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Graphics components")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(components) { component in
                    HStack(spacing: 6) {
                        Image(systemName: "display")
                            .foregroundStyle(.secondary)
                        Text(component.displayName)
                            .foregroundStyle(component.isLegacy ? Color.orange : Color.primary)
                        if component.source == .builtin {
                            Text("Built in")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                }
            }
        }
    }
}
