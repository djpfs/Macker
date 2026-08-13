//===----------------------------------------------------------------------===//
// ComposeView — pick a compose file, see its services, run up/down/logs.
//
// The loaded project, file path, log lines and status are stored in AppState
// so they survive tab switches (the view is recreated each time the sidebar
// selection changes). A recent-history menu lets you quickly reopen compose
// files you've used before.
//===----------------------------------------------------------------------===//

import SwiftUI
import ContainerBackend
import ComposeEngine

/// Manage a docker-compose project: open a file, inspect services, run
/// up/down/restart/logs.
struct ComposeView: View {
    @Environment(AppState.self) private var state
    @AppStorage("logTail") private var logTail = 100
    @State private var isBusy = false
    @State private var showFilePicker = false

    private let orchestrator = ComposeOrchestrator()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let project = state.composeProject {
                projectContent(project)
            } else {
                VStack(spacing: 12) {
                    EmptyStateView(
                        systemImage: "square.stack.3d.up",
                        title: "No compose project",
                        message: "Open a docker-compose.yml file to inspect and manage its services."
                    )
                    if let statusMessage = state.composeStatusMessage {
                        HStack(spacing: 6) {
                            Image(systemName: statusMessage.systemImage)
                                .foregroundStyle(statusMessage.color)
                            Text(statusMessage.text)
                        }
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
        .navigationTitle("Compose")
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.yaml, .plainText, .item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    openFile(url)
                }
            case .failure(let error):
                state.composeStatusMessage = StatusMessage(kind: .error, text: error.localizedDescription)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            if let filePath = state.composeFilePath {
                Text(filePath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("No file selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            historyMenu
            Button {
                showFilePicker = true
            } label: {
                Label("Open…", systemImage: "folder")
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
    }

    /// A menu of recently used compose files for quick reopening.
    @ViewBuilder
    private var historyMenu: some View {
        if !state.composeHistory.isEmpty {
            Menu {
                ForEach(state.composeHistory, id: \.self) { path in
                    Button {
                        openFile(URL(fileURLWithPath: path))
                    } label: {
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Divider()
                Button("Clear history", role: .destructive) {
                    state.clearComposeHistory()
                }
            } label: {
                Label("Recent", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.bordered)
            .help("Recently used compose files")
        }
    }

    @ViewBuilder
    private func projectContent(_ project: ComposeProject) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.title2.bold())
                    Text("\(project.services.count) services")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await runUp(project) }
                } label: {
                    Label("Up", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
                Button {
                    Task { await runDown(project) }
                } label: {
                    Label("Down", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }
            .padding(16)

            if let statusMessage = state.composeStatusMessage {
                HStack(spacing: 6) {
                    Image(systemName: statusMessage.systemImage)
                        .foregroundStyle(statusMessage.color)
                    Text(statusMessage.text)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Divider()

            List {
                ForEach(project.services.keys.sorted(), id: \.self) { name in
                    serviceRow(project: project, name: name)
                }
            }

            if state.composeShowLogs {
                Divider()
                logPanel
            }
        }
    }

    /// A scrollable, monospaced log panel showing progress messages and
    /// container output during compose operations.
    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Logs")
                    .font(.headline)
                Spacer()
                Stepper("Tail: \(logTail)", value: $logTail, in: 10...5000, step: 10)
                    .controlSize(.small)
                Button {
                    copyLogsToClipboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .disabled(state.composeLogLines.isEmpty)
                .help("Copy logs to the clipboard")
                Button {
                    state.clearComposeLog()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(state.composeLogLines.isEmpty)
                .help("Clear logs")
                Button {
                    state.composeShowLogs = false
                } label: {
                    Label("Close", systemImage: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close logs")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            ScrollView {
                Text(state.composeLogLines.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(maxHeight: 220)
            .background(Color.black.opacity(0.05))
        }
    }

    private func serviceRow(project: ComposeProject, name: String) -> some View {
        let service = project.services[name]!
        return HStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.medium))
                Text(service.image ?? service.build?.context ?? "no image")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !service.ports.isEmpty {
                Text(service.ports.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospaced()
            }
            Button {
                Task { await runLogs(project, service: name) }
            } label: {
                Image(systemName: "doc.text")
            }
            .buttonStyle(.borderless)
            .help("Logs for \(name)")
            if service.build != nil {
                Button {
                    Task { await runBuild(project, service: name) }
                } label: {
                    Image(systemName: "hammer")
                }
                .buttonStyle(.borderless)
                .help("Build \(name)")
            }
            Button {
                Task { await runRestart(project, service: name) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Restart \(name)")
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func openFile(_ url: URL) {
        let path = url.path
        do {
            let parsed = try state.loadComposeFile(at: path)
            print("[ComposeView] loaded \(path): \(parsed.services.count) services")
        } catch {
            state.composeStatusMessage = StatusMessage(kind: .error, text: error.localizedDescription)
            print("[ComposeView] failed to load \(path): \(error)")
        }
    }

    /// Accept one or more dropped compose files. The first valid file becomes
    /// the active project; every valid file is recorded in the recent history.
    private func handleDrop(_ urls: [URL]) -> Bool {
        let composeFiles = urls.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "yaml" || ext == "yml"
        }
        guard !composeFiles.isEmpty else { return false }

        var loadedAny = false
        for url in composeFiles {
            let path = url.path
            do {
                let parsed = try state.loadComposeFile(at: path)
                print("[ComposeView] dropped \(path): \(parsed.services.count) services")
                loadedAny = true
            } catch {
                state.composeStatusMessage = StatusMessage(kind: .error, text: error.localizedDescription)
                print("[ComposeView] failed to load \(path): \(error)")
            }
        }
        return loadedAny
    }

    private func runUp(_ project: ComposeProject) async {
        guard let filePath = state.composeFilePath else { return }
        let opID = state.beginOperation("Up \(project.name)", section: .compose)
        defer { state.endOperation(opID) }

        // Record any services that will be built (have a `build:` context) so
        // they show up in the Builds tab.
        var buildIDs: [String: UUID] = [:]
        for (name, service) in project.services where service.build != nil {
            let context = service.build?.context ?? "."
            buildIDs[name] = state.recordBuild(
                ComposeOrchestrator.imageRef(project: project.name, service: name),
                context: context
            )
        }

        let succeeded = await runOperation("Up \(project.name)") { continuation in
            try await orchestrator.up(project: project, filePath: filePath, detached: true, progress: continuation)
        }
        for (_, id) in buildIDs {
            state.finishBuild(id, succeeded: succeeded)
        }
        if succeeded {
            await appendContainerLogs(project)
        }
    }

    private func runDown(_ project: ComposeProject) async {
        let opID = state.beginOperation("Down \(project.name)", section: .compose)
        defer { state.endOperation(opID) }
        await runOperation("Down \(project.name)") { continuation in
            try await orchestrator.down(project: project, progress: continuation)
        }
    }

    private func runRestart(_ project: ComposeProject, service: String) async {
        let opID = state.beginOperation("Restart \(service)", section: .compose)
        defer { state.endOperation(opID) }
        await runOperation("Restart \(service)") { continuation in
            try await orchestrator.restart(project: project, services: [service], progress: continuation)
        }
    }

    private func runBuild(_ project: ComposeProject, service: String) async {
        guard let filePath = state.composeFilePath else { return }
        let opID = state.beginOperation("Build \(service)", section: .compose)
        defer { state.endOperation(opID) }
        let serviceConfig = project.services[service]
        let context = serviceConfig?.build?.context ?? "."
        let buildID = state.recordBuild(
            ComposeOrchestrator.imageRef(project: project.name, service: service),
            context: context
        )
        let succeeded = await runOperation("Build \(service)") { continuation in
            try await orchestrator.build(project: project, filePath: filePath, progress: continuation)
        }
        state.finishBuild(buildID, succeeded: succeeded)
    }

    private func runLogs(_ project: ComposeProject, service: String) async {
        let opID = state.beginOperation("Logs \(service)", section: .compose)
        defer { state.endOperation(opID) }
        isBusy = true
        state.composeShowLogs = true
        state.appendComposeLog("==> Logs for \(service)...")
        defer { isBusy = false }
        let containerName = ComposeOrchestrator.containerName(project: project.name, service: service, config: project.services[service])
        let logService = LogService()
        do {
            for try await line in logService.logs(for: containerName, follow: false, tail: logTail) {
                state.appendComposeLog(line.text)
            }
            state.composeStatusMessage = StatusMessage(kind: .success, text: "Logs for \(service)")
        } catch {
            state.appendComposeLog("[ERROR] \(error.localizedDescription)")
            state.composeStatusMessage = StatusMessage(kind: .error, text: error.localizedDescription)
        }
    }

    /// Run a compose operation, streaming its progress messages into the log
    /// panel so the user sees what's happening instead of a bare spinner.
    /// Returns whether the operation succeeded.
    @discardableResult
    private func runOperation(
        _ title: String,
        _ operation: @escaping @MainActor (AsyncStream<String>.Continuation) async throws -> Void
    ) async -> Bool {
        isBusy = true
        state.composeShowLogs = true
        state.appendComposeLog("==> \(title)")
        defer { isBusy = false }

        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        let logTask = Task { @MainActor in
            for await message in stream {
                state.appendComposeLog(message)
            }
        }

        var succeeded = false
        do {
            try await operation(continuation)
            state.appendComposeLog("[OK] \(title)")
            state.composeStatusMessage = StatusMessage(kind: .success, text: title)
            succeeded = true
            await state.refresh()
        } catch {
            state.appendComposeLog("[ERROR] \(error.localizedDescription)")
            state.composeStatusMessage = StatusMessage(kind: .error, text: error.localizedDescription)
        }
        continuation.finish()
        await logTask.value
        return succeeded
    }

    /// Copy the current compose log lines to the system clipboard.
    private func copyLogsToClipboard() {
        let text = state.composeLogLines.joined(separator: "\n")
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Append the last 50 lines of each service's container output to the log
    /// panel, so `up` shows the actual boot logs.
    private func appendContainerLogs(_ project: ComposeProject) async {
        let logService = LogService()
        let order = (try? ServiceResolver.resolve(project)) ?? []
        for name in order {
            let containerName = ComposeOrchestrator.containerName(project: project.name, service: name, config: project.services[name])
            do {
                for try await line in logService.logs(for: containerName, follow: false, tail: logTail) {
                    state.appendComposeLog("\(name) | \(line.text)")
                }
            } catch {
                state.appendComposeLog("[ERROR] \(name): \(error.localizedDescription)")
            }
        }
    }
}

/// A status message with an SF Symbol icon, shown next to the project header.
struct StatusMessage {
    enum Kind {
        case success
        case error
    }

    let kind: Kind
    let text: String

    var systemImage: String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch kind {
        case .success: .green
        case .error: .red
        }
    }
}
