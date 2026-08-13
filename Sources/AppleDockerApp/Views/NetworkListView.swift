//===----------------------------------------------------------------------===//
// NetworkListView — networks with delete actions.
//===----------------------------------------------------------------------===//

import SwiftUI
import ContainerBackend

/// Lists networks with their mode, subnet, and delete actions.
struct NetworkListView: View {
    @Environment(AppState.self) private var state
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(state.networks.count) networks")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
            Divider()
            if filtered.isEmpty {
                EmptyStateView(
                    systemImage: "network",
                    title: "No networks",
                    message: "Networks are created automatically when containers start."
                )
            } else {
                Table(filtered) {
                    TableColumn("Name") { network in
                        Text(network.name)
                            .font(.body.weight(.medium))
                    }
                    TableColumn("Mode") { network in
                        Text(network.configuration.mode.rawValue)
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Subnet") { network in
                        Text(network.configuration.ipv4Subnet ?? "-")
                            .foregroundStyle(.secondary)
                            .monospaced()
                    }
                    TableColumn("Plugin") { network in
                        Text(network.configuration.plugin)
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("") { network in
                        Button(role: .destructive) {
                            Task { @MainActor in await state.deleteNetwork(network.id) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete \(network.name)")
                    }
                    .width(30)
                }
            }
        }
        .navigationTitle("Networks")
        .searchable(text: $searchText, prompt: "Search networks")
    }

    private var filtered: [NetworkResource] {
        guard !searchText.isEmpty else { return state.networks }
        return state.networks.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.configuration.mode.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }
}
