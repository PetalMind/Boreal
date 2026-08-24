import SwiftUI

struct EnvironmentsView: View {
    @Environment(BorealStore.self) private var store
    let createAction: () -> Void
    @State private var expandedID: UUID?

    var body: some View {
        Group {
            if store.environments.isEmpty {
                ContentUnavailableView {
                    Label("No Environments", systemImage: "externaldrive")
                } description: {
                    Text("Boreal creates an isolated environment for every app by default.")
                } actions: {
                    Button("Create Environment", systemImage: "plus", action: createAction).buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.environments) { environment in
                            environmentCard(environment)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 850)
                }
            }
        }
    }

    private func environmentCard(_ environment: WindowsEnvironment) -> some View {
        VStack(spacing: 0) {
            Button { withAnimation(.snappy) { expandedID = expandedID == environment.id ? nil : environment.id } } label: {
                HStack(spacing: 16) {
                    Image(systemName: "externaldrive.fill").font(.title2).foregroundStyle(.tint).frame(width: 38, height: 38).background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(environment.name).font(.headline)
                        Text("\(environment.windowsVersion) · \(store.applications(in: environment.id).count) \(store.applications(in: environment.id).count == 1 ? "app" : "apps")").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(store.formattedBytes(environment.storageBytes)).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary).rotationEffect(.degrees(expandedID == environment.id ? 90 : 0))
                }.padding(16).contentShape(Rectangle())
            }.buttonStyle(.plain)

            if expandedID == environment.id {
                Divider()
                VStack(spacing: 2) {
                    DetailRow(title: "Runtime", value: environment.runtime, symbol: "gearshape.2")
                    DetailRow(title: "Architecture", value: environment.architecture, symbol: "cpu")
                    DetailRow(title: "Graphics", value: environment.graphics, symbol: "display")
                    HStack {
                        Button("Open C: Drive", systemImage: "folder") { }
                        Button("Repair", systemImage: "wrench.and.screwdriver") { }
                        Spacer()
                        Button("Delete", systemImage: "trash", role: .destructive) { store.removeEnvironment(environment.id) }
                    }.padding(.top, 10)
                }.padding(16)
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.separator.opacity(0.7), lineWidth: 0.5))
    }
}

