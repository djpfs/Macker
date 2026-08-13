//===----------------------------------------------------------------------===//
// ContainerFilesView — browse a container's filesystem.
//
// The container's rootfs is exported and extracted into a temporary folder,
// then browsed with a simple file explorer (OrbStack-style "Files" tab).
//===----------------------------------------------------------------------===//

import SwiftUI
import ContainerBackend

/// A file browser for a container's filesystem.
struct ContainerFilesView: View {
    let containerID: String
    @State private var rootURL: URL?
    @State private var currentURL: URL?
    @State private var entries: [FileEntry] = []
    @State private var isLoading = true
    @State private var errorText: String?

    struct FileEntry: Identifiable {
        let id = UUID()
        let name: String
        let isDirectory: Bool
        let size: Int64
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Exporting container filesystem…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText {
                ContentUnavailableView {
                    Label("Could not load files", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorText)
                }
            } else {
                pathBar
                Divider()
                fileList
            }
        }
        .task { await load() }
    }

    private var pathBar: some View {
        HStack(spacing: 6) {
            Button {
                navigate(to: rootURL)
            } label: {
                Image(systemName: "house")
            }
            .buttonStyle(.borderless)
            .disabled(currentURL == rootURL)

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
        guard let rootURL, let currentURL else { return "/" }
        let root = rootURL.path
        let current = currentURL.path
        if current == root { return "/" }
        return String(current.dropFirst(root.count))
    }

    private var fileList: some View {
        List {
            if currentURL != rootURL {
                Button {
                    navigate(to: currentURL?.deletingLastPathComponent())
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
                    if entry.isDirectory, let currentURL {
                        navigate(to: currentURL.appendingPathComponent(entry.name))
                    }
                }
            }
        }
    }

    private func navigate(to url: URL?) {
        guard let url else { return }
        currentURL = url
        reload()
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

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fm = FileManager.default
            let dir = fm.temporaryDirectory
                .appendingPathComponent("macker-files-\(containerID)", isDirectory: true)
            try? fm.removeItem(at: dir)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)

            let archive = dir.appendingPathComponent("rootfs.tar")
            let service = ContainerService()
            try await service.exportContainer(id: containerID, archive: archive)

            let extractDir = dir.appendingPathComponent("rootfs", isDirectory: true)
            try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xf", archive.path, "-C", extractDir.path]
            try process.run()
            process.waitUntilExit()

            rootURL = extractDir
            currentURL = extractDir
            reload()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
