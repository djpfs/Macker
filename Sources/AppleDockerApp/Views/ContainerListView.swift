//===----------------------------------------------------------------------===//
// ContainerListView — all containers with start/stop/restart/delete actions.
//
// OrbStack-style: filter (all/running/stopped), sort, and grouping of
// containers by their compose project (or "Standalone" for non-compose ones).
//
// Uses a custom HStack layout (instead of a nested NavigationSplitView) so the
// sidebar keeps a stable minimum width and is never squeezed by the detail
// pane. The sidebar is resizable via a drag handle.
//===----------------------------------------------------------------------===//

import SwiftUI
import ContainerBackend
import ComposeEngine

/// Lists containers with per-row actions and a detail pane.
struct ContainerListView: View {
    @Environment(AppState.self) private var state
    @State private var selection: String?
    @State private var searchText = ""
    @State private var filter: ContainerFilter = .all
    @State private var sort: ContainerSort = .name
    @State private var sidebarWidth: CGFloat = 280
    @State private var isResizing = false
    @State private var resizeStartWidth: CGFloat = 280
    private let orchestrator = ComposeOrchestrator()

    enum ContainerFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case running = "Running"
        case stopped = "Stopped"
        var id: String { rawValue }
    }

    enum ContainerSort: String, CaseIterable, Identifiable {
        case name = "Name"
        case status = "Status"
        case image = "Image"
        var id: String { rawValue }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth)
            resizer
            detail
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchField
            controls
            Divider()
            list
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search containers", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    /// Filter + sort controls. Fixed height so it never grows when a filter
    /// (e.g. "Stopped") is selected.
    private var controls: some View {
        HStack(spacing: 6) {
            filterControl
            sortControl
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: 36)
    }

    private var filterControl: some View {
        HStack(spacing: 2) {
            ForEach(ContainerFilter.allCases) { f in
                Button {
                    filter = f
                } label: {
                    Text(f.rawValue)
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(filter == f ? Color.accentColor : Color.clear)
                        .foregroundStyle(filter == f ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 24)
    }

    private var sortControl: some View {
        Picker("Sort", selection: $sort) {
            ForEach(ContainerSort.allCases) { s in
                Label(s.rawValue, systemImage: sortIcon(s)).tag(s)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.small)
    }

    private var resizer: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 6)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isResizing {
                                    isResizing = true
                                    resizeStartWidth = sidebarWidth
                                }
                                sidebarWidth = max(240, min(420, resizeStartWidth + value.translation.width))
                            }
                            .onEnded { _ in
                                isResizing = false
                            }
                    )
            )
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            if let selection, let container = state.containers.first(where: { $0.id == selection }) {
                // `.id(container.id)` forces the whole detail subtree to be
                // recreated when the selected container changes, so tab views
                // that hold @State (e.g. Settings) don't keep stale data.
                ContainerDetailView(container: container)
                    .id(container.id)
            } else {
                EmptyStateView(
                    systemImage: "shippingbox",
                    title: "Select a container",
                    message: "Choose a container from the list to see its details, logs and stats."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sortIcon(_ s: ContainerSort) -> String {
        switch s {
        case .name: "textformat"
        case .status: "circle.fill"
        case .image: "photo"
        }
    }

    private var filtered: [ContainerSnapshot] {
        var result = state.containers
        switch filter {
        case .all: break
        case .running: result = result.filter { $0.status == .running }
        case .stopped: result = result.filter { $0.status != .running }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.id.localizedCaseInsensitiveContains(searchText)
                    || $0.configuration.image.reference.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sort {
        case .name: result.sort { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
        case .status: result.sort { ($0.status == .running ? 0 : 1) < ($1.status == .running ? 0 : 1) }
        case .image: result.sort { $0.configuration.image.reference.localizedCaseInsensitiveCompare($1.configuration.image.reference) == .orderedAscending }
        }
        return result
    }

    /// Group containers by compose project, then by name.
    private var grouped: [(name: String, containers: [ContainerSnapshot])] {
        let filtered = filtered
        let groups = Dictionary(grouping: filtered) { container in
            container.configuration.labels["com.docker.compose.project"] ?? "Standalone"
        }
        return groups
            .map { (name: $0.key, containers: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var list: some View {
        Group {
            if filtered.isEmpty {
                // Compact empty state. ContentUnavailableView has a large
                // intrinsic size that, inside the sidebar VStack, would expand
                // and push the layout (the "grows to the middle of the screen"
                // bug when a filter like Stopped matches nothing).
                VStack(spacing: 8) {
                    Image(systemName: "shippingbox")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No containers")
                        .font(.callout.weight(.medium))
                    Text("Run a container with `docker run`, or use `docker compose up`.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
            } else {
                List(selection: $selection) {
                    ForEach(grouped, id: \.name) { group in
                        Section {
                            ForEach(group.containers) { container in
                                ContainerRow(container: container)
                                    .tag(container.id)
                                    .contextMenu {
                                        Button("Start") { Task { @MainActor in await state.startContainer(container.id) } }
                                            .disabled(container.status == .running)
                                        Button("Stop") { Task { @MainActor in await state.stopContainer(container.id) } }
                                            .disabled(container.status != .running)
                                        Button("Restart") { Task { @MainActor in await state.restartContainer(container.id) } }
                                            .disabled(container.status != .running)
                                        Divider()
                                        Button("Delete", role: .destructive) {
                                            Task { @MainActor in await state.deleteContainer(container.id) }
                                        }
                                    }
                            }
                        } header: {
                            HStack(spacing: 4) {
                                Image(systemName: group.name == "Standalone" ? "shippingbox" : "square.stack.3d.up")
                                    .font(.caption)
                                Text(group.name)
                                    .font(.caption.weight(.semibold))
                                Text("\(group.containers.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if group.name != "Standalone" {
                                    Menu {
                                        Button("Up") { projectUp(group) }
                                        Button("Stop") { projectStop(group) }
                                        Button("Restart") { projectRestart(group) }
                                        Button("Recreate") { projectRecreate(group) }
                                        Divider()
                                        Button("Down", role: .destructive) { projectDown(group) }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                    }
                                    .menuStyle(.borderlessButton)
                                    .menuIndicator(.hidden)
                                    .fixedSize()
                                    .help("Project actions")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Project-level compose actions

    /// The compose file path for a group, or nil for standalone containers.
    private func composeFilePath(for group: (name: String, containers: [ContainerSnapshot])) -> String? {
        guard group.name != "Standalone" else { return nil }
        return group.containers.first?.configuration.labels["com.docker.compose.project.config_files"]
    }

    /// Run a compose operation against the whole project, streaming progress to
    /// the compose log panel and tagging it as a background operation.
    private func runProject(
        _ title: String,
        group: (name: String, containers: [ContainerSnapshot]),
        _ body: @escaping @MainActor (ComposeProject, String, AsyncStream<String>.Continuation) async throws -> Void,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        guard let filePath = composeFilePath(for: group) else { return }
        Task { @MainActor in
            do {
                let project = try state.loadComposeFile(at: filePath)
                let opID = state.beginOperation(title, section: .containers)
                defer { state.endOperation(opID) }
                let (stream, continuation) = AsyncStream.makeStream(of: String.self)
                let logTask = Task { @MainActor in
                    for await message in stream {
                        state.appendComposeLog(message)
                    }
                }
                var succeeded = false
                do {
                    try await body(project, filePath, continuation)
                    state.appendComposeLog("[OK] \(title)")
                    succeeded = true
                    await state.refresh()
                } catch {
                    state.appendComposeLog("[ERROR] \(error.localizedDescription)")
                }
                continuation.finish()
                await logTask.value
                completion?(succeeded)
            } catch {
                state.composeStatusMessage = StatusMessage(kind: .error, text: error.localizedDescription)
            }
        }
    }

    /// Record a build entry for every service in the group that has a
    /// `build:` context, returning the recorded build IDs.
    private func recordBuilds(for group: (name: String, containers: [ContainerSnapshot])) -> [UUID] {
        guard let filePath = composeFilePath(for: group),
              let project = try? state.loadComposeFile(at: filePath) else { return [] }
        var ids: [UUID] = []
        for (name, service) in project.services where service.build != nil {
            let context = service.build?.context ?? "."
            ids.append(state.recordBuild(
                ComposeOrchestrator.imageRef(project: project.name, service: name),
                context: context
            ))
        }
        return ids
    }

    /// Mark recorded builds as finished with the given outcome.
    private func finishBuilds(_ ids: [UUID], succeeded: Bool) {
        for id in ids {
            state.finishBuild(id, succeeded: succeeded)
        }
    }

    private func projectUp(_ group: (name: String, containers: [ContainerSnapshot])) {
        let buildIDs = recordBuilds(for: group)
        runProject("Up \(group.name)", group: group) { project, filePath, continuation in
            try await orchestrator.up(project: project, filePath: filePath, detached: true, progress: continuation)
        } completion: { succeeded in
            finishBuilds(buildIDs, succeeded: succeeded)
        }
    }

    private func projectStop(_ group: (name: String, containers: [ContainerSnapshot])) {
        runProject("Stop \(group.name)", group: group) { project, _, continuation in
            try await orchestrator.stop(project: project, services: [], progress: continuation)
        }
    }

    private func projectRestart(_ group: (name: String, containers: [ContainerSnapshot])) {
        runProject("Restart \(group.name)", group: group) { project, _, continuation in
            try await orchestrator.restart(project: project, services: [], progress: continuation)
        }
    }

    private func projectRecreate(_ group: (name: String, containers: [ContainerSnapshot])) {
        let buildIDs = recordBuilds(for: group)
        runProject("Recreate \(group.name)", group: group) { project, filePath, continuation in
            try await orchestrator.recreate(project: project, filePath: filePath, progress: continuation)
        } completion: { succeeded in
            finishBuilds(buildIDs, succeeded: succeeded)
        }
    }

    private func projectDown(_ group: (name: String, containers: [ContainerSnapshot])) {
        runProject("Down \(group.name)", group: group) { project, _, continuation in
            try await orchestrator.down(project: project, progress: continuation)
        }
    }
}

/// A single container row with status dot, name, image, and quick actions.
struct ContainerRow: View {
    @Environment(AppState.self) private var state
    let container: ContainerSnapshot

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(status: container.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(container.id)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(container.configuration.image.reference)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if container.status == .running {
                    Button {
                        Task { @MainActor in await state.stopContainer(container.id) }
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Stop")
                } else {
                    Button {
                        Task { @MainActor in await state.startContainer(container.id) }
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Start")
                }
                Button {
                    Task { @MainActor in await state.restartContainer(container.id) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(container.status != .running)
                .help("Restart")
            }
        }
        .padding(.vertical, 2)
    }
}
