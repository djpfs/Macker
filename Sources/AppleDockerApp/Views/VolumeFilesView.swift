//===----------------------------------------------------------------------===//
// VolumeFilesView — browse a named volume's filesystem on the host.
//
// A volume's `source` is a host directory, so we can browse it directly with
// a simple file explorer (OrbStack-style volume file explorer).
//===----------------------------------------------------------------------===//

import SwiftUI
import ContainerBackend

/// A file browser for a named volume's host directory.
struct VolumeFilesView: View {
    @Environment(\.dismiss) private var dismiss
    let volume: VolumeConfiguration
    @State private var currentURL: URL?
    @State private var entries: [FileEntry] = []
    @State private var errorText: String?

    struct FileEntry: Identifiable {
        let id = UUID()
        let name: String
        let isDirectory: Bool
        let size: Int64
    }

    var body: some View {
        VStack(spacing: 0) {
            if let errorText {
                ContentUnavailableView {
                    Label("Could not load volume", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorText)
                }
            } else {
                pathBar
                Divider()
                fileList
            }
        }
        .navigationTitle(volume.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark")
                }
                .help("Close")
            }
        }
        .onAppear {
            currentURL = URL(fileURLWithPath: volume.source)
            reload()
        }
    }

    private var pathBar: some View {
        HStack(spacing: 6) {
            Button {
                currentURL = URL(fileURLWithPath: volume.source)
                reload()
            } label: {
                Image(systemName: "house")
            }
            .buttonStyle(.borderless)

            Text(relativePath)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
            Button("Reveal in Finder") {
                if let currentURL {
                    NSWorkspace.shared.activateFileViewerSelecting([currentURL])
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
    }

    private var relativePath: String {
        guard let currentURL else { return "/" }
        let root = URL(fileURLWithPath: volume.source).path
        let current = currentURL.path
        if current == root { return "/" }
        return String(current.dropFirst(root.count))
    }

    private var fileList: some View {
        List {
            if let dir = currentURL, dir.path != URL(fileURLWithPath: volume.source).path {
                Button {
                    currentURL = dir.deletingLastPathComponent()
                    reload()
                } label: {
                    Label("..", systemImage: "arrow.up")
                }
            }
            ForEach(entries) { entry in
                HStack(spacing: 8) {
                    Image(systemName: entry.isDirectory ? "folder" : "doc")
                        .foregroundStyle(entry.isDirectory ? .blue : .secondary)
                    Text(entry.name)
                    Spacer()
                    if !entry.isDirectory {
                        Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if entry.isDirectory, let dir = currentURL {
                        currentURL = dir.appendingPathComponent(entry.name)
                        reload()
                    }
                }
            }
        }
    }

    private func reload() {
        guard let currentURL else { return }
        let fm = FileManager.default
        do {
            let items = try fm.contentsOfDirectory(at: currentURL, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])
            entries = items.map { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                return FileEntry(
                    name: url.lastPathComponent,
                    isDirectory: values?.isDirectory ?? false,
                    size: Int64(values?.fileSize ?? 0)
                )
            }
            .sorted { $0.isDirectory && !$1.isDirectory }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
