//===----------------------------------------------------------------------===//
// ImageListView — local images with pull/delete actions.
//===----------------------------------------------------------------------===//

import SwiftUI
import ContainerBackend

/// Lists local images with a pull sheet and per-row delete.
struct ImageListView: View {
    @Environment(AppState.self) private var state
    @State private var searchText = ""
    @State private var showPullSheet = false
    @State private var pullReference = ""
    @State private var imageToDelete: ImageSummary?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if filtered.isEmpty {
                EmptyStateView(
                    systemImage: "photo.on.rectangle",
                    title: "No images",
                    message: "Pull an image to get started, e.g. `nginx` or `node:22-alpine`."
                )
            } else {
                Table(filtered) {
                    TableColumn("Repository") { image in
                        Text(image.repository)
                            .font(.body.weight(.medium))
                    }
                    TableColumn("Tag") { image in
                        Text(image.tag ?? "latest")
                    }
                    TableColumn("ID") { image in
                        Text(String(image.id.prefix(12)))
                            .foregroundStyle(.secondary)
                            .monospaced()
                    }
                    TableColumn("Size") { image in
                        Text(ByteCountFormatter.string(fromByteCount: Int64(image.size), countStyle: .file))
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Created") { image in
                        Text(image.creationDate.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Platform") { image in
                        Text(image.platform ?? "-")
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("") { image in
                        Button(role: .destructive) {
                            imageToDelete = image
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete \(image.name)")
                    }
                    .width(30)
                }
            }
        }
        .navigationTitle("Images")
        .searchable(text: $searchText, prompt: "Search images")
        .sheet(isPresented: $showPullSheet) {
            pullSheet
        }
        .confirmationDialog(
            "Delete Image?",
            isPresented: Binding(
                get: { imageToDelete != nil },
                set: { if !$0 { imageToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let image = imageToDelete {
                    Task { @MainActor in await state.deleteImage(image.name) }
                }
                imageToDelete = nil
            }
            Button("Cancel", role: .cancel) { imageToDelete = nil }
        } message: {
            Text("Delete \(imageToDelete?.name ?? "")? This cannot be undone.")
        }
    }

    private var filtered: [ImageSummary] {
        guard !searchText.isEmpty else { return state.images }
        return state.images.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var toolbar: some View {
        HStack {
            Text("\(state.images.count) images")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                showPullSheet = true
            } label: {
                Label("Pull", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
    }

    private var pullSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pull Image")
                .font(.title2.bold())
            TextField("e.g. nginx, node:22-alpine", text: $pullReference)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submitPull() }
            HStack {
                Spacer()
                Button("Cancel") { showPullSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Pull") { submitPull() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(pullReference.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func submitPull() {
        let ref = pullReference.trimmingCharacters(in: .whitespaces)
        guard !ref.isEmpty else { return }
        showPullSheet = false
        pullReference = ""
        Task { @MainActor in await state.pullImage(ref) }
    }
}
