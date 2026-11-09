import SwiftUI

struct RootView: View {
    let client: RemoteClient

    var body: some View {
        NavigationStack {
            if client.isConnected { ControlView(client: client) } else { MacListView(client: client) }
        }
        .animation(.smooth, value: client.isConnected)
        .sensoryFeedback(.success, trigger: client.isConnected) { _, connected in connected }
    }
}

/// Which controls the remote shows; stored only on this iPhone.
enum RemoteLayout: String, CaseIterable, Identifiable {
    case all, text, slides
    var id: Self { self }
    var title: String {
        switch self { case .all: "Alles"; case .text: "Tempo und Text"; case .slides: "Nur Folien" }
    }
    var symbol: String {
        switch self { case .all: "square.grid.2x2"; case .text: "text.alignleft"; case .slides: "rectangle.on.rectangle" }
    }
}

/// Grouped surface for the content layer; Liquid Glass stays on the controls.
struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26, style: .continuous))
    }
}
