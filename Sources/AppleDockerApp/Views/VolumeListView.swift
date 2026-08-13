//===----------------------------------------------------------------------===//
// VolumeListView — named volumes with delete actions.
//===----------------------------------------------------------------------===//

import SwiftUI
import ContainerBackend

/// Lists named volumes with size and delete actions.
struct VolumeListView: View {
    @Environment(AppState.self) private var state
    @State private var searchText = ""
    @State private var browsingVolume: VolumeConfiguration?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(state.volumes.count) volumes")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
            Divider()
            if filtered.isEmpty {
                EmptyStateView(
                    systemImage: "externaldrive",
                    title: "No volumes",
                    message: "Volumes are created automatically when a container mounts a named volume."
                )
            } else {
                Table(filtered) {
                    TableColumn("Name") { volume in
                        Text(volume.name)
                            .font(.body.weight(.medium))
                    }
                    TableColumn("Driver") { volume in
                        Text(volume.driver)
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Format") { volume in
                        Text(volume.format)
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Size") { volume in
                        Text(volume.sizeInBytes.map {
                            ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
                        } ?? "-")
                        .foregroundStyle(.secondary)
                    }
                    TableColumn("Created") { volume in
                        Text(volume.creationDate.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("") { volume in
                        HStack(spacing: 6) {
                            Button {
                                browsingVolume = volume
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.borderless)
                            .help("Browse \(volume.name)")
                            Button(role: .destructive) {
                                Task { @MainActor in await state.deleteVolume(volume.name) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete \(volume.name)")
                        }
                    }
                    .width(60)
                }
            }
        }
        .navigationTitle("Volumes")
        .searchable(text: $searchText, prompt: "Search volumes")
        .sheet(item: $browsingVolume) { volume in
            VolumeFilesView(volume: volume)
                .frame(minWidth: 500, minHeight: 400)
        }
    }

    private var filtered: [VolumeConfiguration] {
        guard !searchText.isEmpty else { return state.volumes }
        return state.volumes.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.driver.localizedCaseInsensitiveContains(searchText)
        }
    }
}
