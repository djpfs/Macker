//===----------------------------------------------------------------------===//
// BuildsView — history of image builds (BuildKit via `container build`).
//
// Shows recent builds with their status, image reference, build context and
// duration, plus actions to build a new image, prune the build cache, retry a
// failed build and copy the underlying build command.
//===----------------------------------------------------------------------===//

import SwiftUI
import AppKit
import ContainerBackend

/// The Builds tab: a list of recent image builds with build actions.
struct BuildsView: View {
    @Environment(AppState.self) private var state

    @State private var showBuildSheet = false
    @State private var buildContext = ""
    @State private var buildTag = ""
    @State private var buildDockerfile = ""
    @State private var buildNoCache = false
    @State private var buildOutput: String?
    @State private var showOutput = false
    @State private var pruneConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if state.buildHistory.isEmpty {
                EmptyStateView(
                    systemImage: "hammer",
                    title: "No builds yet",
                    message: "Builds from compose `build:` services and image builds will appear here."
                )
            } else {
                List {
                    ForEach(state.buildHistory) { build in
                        buildRow(build)
                    }
                }
            }
        }
        .navigationTitle("Builds")
        .sheet(isPresented: $showBuildSheet) {
            buildSheet
        }
        .sheet(isPresented: $showOutput) {
            outputSheet
        }
        .confirmationDialog(
            "Prune build cache?",
            isPresented: $pruneConfirm,
            titleVisibility: .visible
        ) {
            Button("Prune", role: .destructive) {
                Task { @MainActor in await state.deleteBuildkitBuilder() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes the buildkit builder container, freeing the build cache (snapshots from `container build`). It is recreated on the next build.")
        }
    }

    private var header: some View {
        HStack {
            Text("\(state.buildHistory.count) build\(state.buildHistory.count == 1 ? "" : "s")")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                showBuildSheet = true
            } label: {
                Label("Build", systemImage: "hammer")
            }
            .buttonStyle(.borderedProminent)
            Button {
                pruneConfirm = true
            } label: {
                Label("Prune cache", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            if !state.buildHistory.isEmpty {
                Button("Clear", role: .destructive) {
                    state.clearBuildHistory()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
    }

    private func buildRow(_ build: BuildRecord) -> some View {
        HStack(spacing: 10) {
            statusIcon(build)
            VStack(alignment: .leading, spacing: 2) {
                Text(build.reference)
                    .font(.body.weight(.medium))
                Text(build.context)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let detail = build.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(durationText(build))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospaced()
            if build.succeeded == false {
                Button {
                    Task { @MainActor in
                        let output = await state.buildImage(context: build.context, tag: build.reference)
                        buildOutput = output
                        showOutput = true
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Retry build")
            }
            Button {
                copyCommand(build)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy build command")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusIcon(_ build: BuildRecord) -> some View {
        if let succeeded = build.succeeded {
            if succeeded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    private func durationText(_ build: BuildRecord) -> String {
        let end = build.finishedAt ?? Date()
        let interval = end.timeIntervalSince(build.startedAt)
        if interval < 1 {
            return "<1s"
        }
        return String(format: "%.0fs", interval)
    }

    private func copyCommand(_ build: BuildRecord) {
        let cmd = "container build --progress plain -t \(build.reference) \(build.context)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
    }

    // MARK: - Build sheet

    private var buildSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Build Image")
                .font(.title2.bold())
            HStack {
                TextField("Context directory", text: $buildContext)
                    .textFieldStyle(.roundedBorder)
                Button("Browse...") { pickContext() }
            }
            TextField("Tag (e.g. myapp:latest)", text: $buildTag)
                .textFieldStyle(.roundedBorder)
            TextField("Dockerfile (optional)", text: $buildDockerfile)
                .textFieldStyle(.roundedBorder)
            Toggle("No cache", isOn: $buildNoCache)
            HStack {
                Spacer()
                Button("Cancel") { showBuildSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Build") { submitBuild() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(buildContext.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func pickContext() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            buildContext = url.path
        }
    }

    private func submitBuild() {
        let context = buildContext.trimmingCharacters(in: .whitespaces)
        guard !context.isEmpty else { return }
        let tag = buildTag.trimmingCharacters(in: .whitespaces)
        let dockerfile = buildDockerfile.trimmingCharacters(in: .whitespaces)
        showBuildSheet = false
        buildContext = ""
        buildTag = ""
        buildDockerfile = ""
        buildNoCache = false
        Task { @MainActor in
            let output = await state.buildImage(
                context: context,
                tag: tag.isEmpty ? nil : tag,
                dockerfile: dockerfile.isEmpty ? nil : dockerfile,
                noCache: buildNoCache
            )
            buildOutput = output
            showOutput = true
        }
    }

    // MARK: - Output sheet

    private var outputSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Build Output")
                .font(.title2.bold())
            ScrollView {
                Text(buildOutput ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 200, maxHeight: 400)
            HStack {
                Spacer()
                Button("Close") { showOutput = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 420)
    }
}
