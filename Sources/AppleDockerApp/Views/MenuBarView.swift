//===----------------------------------------------------------------------===//
// MenuBarView — menu bar extra with resource rings, configurable metrics,
// grouped container quick list, and quick actions.
//===----------------------------------------------------------------------===//

import SwiftUI
import AppKit
import ContainerBackend

/// The menu bar extra. Which metrics and controls appear is driven by the
/// `MenuBarConfig` edited in Settings (persisted via @AppStorage).
struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @AppStorage("menuBarConfig") private var config = MenuBarConfig()

    @State private var logsRequest: LogsRequest?

    /// Identifiable wrapper so `.sheet(item:)` can present a container's logs.
    private struct LogsRequest: Identifiable {
        let id: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if config.hasMetrics {
                metrics
            }

            if config.activeItems.contains(.containerList) {
                Divider()
                if state.containers.isEmpty {
                    Text("No containers")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                } else {
                    containerList
                }
            }

            if config.hasControls {
                Divider()
                controls
            }

            Divider()
            footer
        }
        .padding(8)
        .frame(width: 300)
        .sheet(item: $logsRequest) { request in
            LogsSheet(containerID: request.id)
        }
    }

    // MARK: - Metrics

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                if config.activeItems.contains(.cpuRing) {
                    ring(
                        value: state.totalCPUPercent / 100,
                        label: "CPU",
                        color: .blue
                    )
                }
                if config.activeItems.contains(.memoryRing) {
                    ring(
                        value: state.totalMemoryLimitBytes > 0
                            ? Double(state.totalMemoryBytes) / Double(state.totalMemoryLimitBytes)
                            : 0,
                        label: "Mem",
                        color: .orange
                    )
                }
                Spacer()
                if config.activeItems.contains(.runtimeStatus) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Macker")
                            .font(.headline)
                        Text(state.isDaemonRunning ? "Runtime running" : "Runtime unreachable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 4)

            if !textMetrics.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                    GridItem(.flexible(), alignment: .trailing)],
                          alignment: .leading, spacing: 4) {
                    ForEach(textMetrics, id: \.label) { metric in
                        Text(metric.label)
                            .foregroundStyle(.secondary)
                        Text(metric.value)
                            .fontWeight(.medium)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    /// The enabled text-based metrics as (label, value) pairs.
    private var textMetrics: [(label: String, value: String)] {
        var metrics: [(String, String)] = []
        if config.activeItems.contains(.memoryUsed) {
            metrics.append(("Memory used", formatBytes(state.totalMemoryBytes)))
        }
        if config.activeItems.contains(.memoryLimit) {
            metrics.append(("Memory limit", formatBytes(state.totalMemoryLimitBytes)))
        }
        if config.activeItems.contains(.runningCount) {
            metrics.append(("Running", "\(state.runningCount)"))
        }
        if config.activeItems.contains(.containerCount) {
            metrics.append(("Containers", "\(state.containers.count)"))
        }
        if config.activeItems.contains(.imageCount) {
            metrics.append(("Images", "\(state.images.count)"))
        }
        if config.activeItems.contains(.volumeCount) {
            metrics.append(("Volumes", "\(state.volumes.count)"))
        }
        if config.activeItems.contains(.networkCount) {
            metrics.append(("Networks", "\(state.networks.count)"))
        }
        if config.activeItems.contains(.diskUsed) {
            metrics.append(("Disk used", formatBytes(state.diskUsage.totalSize ?? 0)))
        }
        return metrics
    }

    // MARK: - Container list (grouped by compose project)

    /// A group of containers sharing a compose project (or standalone).
    private struct ContainerGroup: Identifiable {
        let id: String
        let title: String
        let containers: [ContainerSnapshot]
    }

    /// Containers grouped by their `com.docker.compose.project` label.
    /// Standalone containers (no project label) each form their own group.
    private var containerGroups: [ContainerGroup] {
        let projectKey = "com.docker.compose.project"
        var byProject: [String: [ContainerSnapshot]] = [:]
        var standalone: [ContainerSnapshot] = []
        for container in state.containers {
            if let project = container.configuration.labels[projectKey], !project.isEmpty {
                byProject[project, default: []].append(container)
            } else {
                standalone.append(container)
            }
        }
        var groups: [ContainerGroup] = []
        for (project, containers) in byProject.sorted(by: { $0.key < $1.key }) {
            groups.append(ContainerGroup(id: "project-\(project)", title: project, containers: containers))
        }
        for container in standalone {
            groups.append(ContainerGroup(id: "standalone-\(container.id)", title: container.id, containers: [container]))
        }
        return groups
    }

    private var containerList: some View {
        ForEach(containerGroups) { group in
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)

                ForEach(group.containers.prefix(config.maxContainers)) { container in
                    containerRow(container)
                }
            }
        }
    }

    private func containerRow(_ container: ContainerSnapshot) -> some View {
        HStack(spacing: 8) {
            StatusDot(status: container.status)
            Text(container.id)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Menu {
                if container.status == .running {
                    Button("Logs") { logsRequest = LogsRequest(id: container.id) }
                    Button("Restart") {
                        Task { @MainActor in await state.restartContainer(container.id) }
                    }
                    Button("Stop") {
                        Task { @MainActor in await state.stopContainer(container.id) }
                    }
                    Divider()
                    Button("Recreate") {
                        Task { @MainActor in await state.recreateContainer(container.id) }
                    }
                    Button("Remove", role: .destructive) {
                        Task { @MainActor in await state.deleteContainer(container.id) }
                    }
                } else {
                    Button("Start") {
                        Task { @MainActor in await state.startContainer(container.id) }
                    }
                    Button("Logs") { logsRequest = LogsRequest(id: container.id) }
                    Divider()
                    Button("Remove", role: .destructive) {
                        Task { @MainActor in await state.deleteContainer(container.id) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
            .menuIconHover()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Controls

    /// The configurable quick controls (Refresh / Actions) shown above the
    /// footer.
    private var controls: some View {
        Group {
            if config.activeItems.contains(.refresh) {
                Button("Refresh") {
                    Task { @MainActor in await state.refresh() }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
                .menuHover()
            }

            if config.activeItems.contains(.actions) {
                Menu {
                    runtimeMenu
                } label: {
                    Label("Ações", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
                .menuHover()
            }
        }
    }

    /// The runtime / app commands shared by the Actions menu and the footer.
    private var runtimeMenu: some View {
        Group {
            Button("Parar serviço") {
                Task { @MainActor in await state.stopDaemon() }
            }
            .disabled(!state.isDaemonRunning)

            Button("Reiniciar") {
                Task { @MainActor in await state.restartDaemon() }
            }

            Divider()

            Button("Prune build cache") {
                Task { @MainActor in await state.deleteBuildkitBuilder() }
            }
            .help("Deletes the buildkit builder, freeing the build cache (can be tens of GB). Recreated on the next build.")

            Divider()

            Button("Restaurar UI padrão") {
                config = MenuBarConfig()
            }

            Divider()

            Button("Fechar Macker", role: .destructive) {
                NSApp.terminate(nil)
            }
        }
    }

    /// The footer: a prominent "Open Macker" button plus a compact row
    /// of icon actions (Refresh, Runtime, Restore, Quit).
    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                openWindow(id: "main")
            } label: {
                Label("Open Macker", systemImage: "shippingbox")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            HStack(spacing: 4) {
                if config.activeItems.contains(.refresh) {
                    footerIcon("arrow.clockwise", "Refresh") {
                        Task { @MainActor in await state.refresh() }
                    }
                }
                if config.activeItems.contains(.actions) {
                    Menu {
                        runtimeMenu
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIconHover()
                    .help("Ações")
                }
                Spacer()
            }
        }
    }

    /// A small circular icon button used in the footer action row.
    private func footerIcon(_ systemImage: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .menuIconHover()
        .help(help)
    }

    private func ring(value: Double, label: String, color: Color) -> some View {
        Gauge(value: min(max(value, 0), 1), in: 0...1) {
            Text(label)
        } currentValueLabel: {
            Text("\(Int(value * 100))%")
                .font(.caption2)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(color)
        .frame(width: 44, height: 44)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// A sheet that streams a container's logs.
private struct LogsSheet: View {
    let containerID: String
    @Environment(\.dismiss) private var dismiss
    @AppStorage("logTail") private var tail = 100
    @State private var lines: [String] = []
    @State private var follow = true
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Logs — \(containerID)")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding(12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: lines.count) {
                    if follow, let last = lines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            .frame(minHeight: 300)

            Divider()

            HStack {
                Toggle("Follow", isOn: $follow)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Stepper("Tail: \(tail)", value: $tail, in: 10...5000, step: 10)
                    .controlSize(.small)
                    .onChange(of: tail) { startStreaming() }
                Button("Clear") { lines.removeAll() }
                    .controlSize(.small)
            }
            .padding(10)
        }
        .frame(width: 520, height: 420)
        .onAppear { startStreaming() }
        .onDisappear { task?.cancel() }
    }

    private func startStreaming() {
        task?.cancel()
        task = Task {
            let logService = LogService()
            do {
                for try await line in logService.logs(for: containerID, follow: true, tail: tail) {
                    if Task.isCancelled { break }
                    lines.append(line.text)
                    if lines.count > 2000 {
                        lines.removeFirst(lines.count - 2000)
                    }
                }
            } catch {
                lines.append("[ERROR] \(error.localizedDescription)")
            }
        }
    }
}

/// Highlights a menu-bar row on hover so items read as interactive.
private struct MenuHover: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                hovering ? Color.accentColor.opacity(0.15) : Color.clear
            )
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .onHover { hovering = $0 }
    }
}

extension View {
    fileprivate func menuHover() -> some View {
        modifier(MenuHover())
    }
}

/// Highlights a small circular icon button on hover.
private struct MenuIconHover: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(3)
            .background(
                hovering ? Color.accentColor.opacity(0.25) : Color.clear
            )
            .clipShape(Circle())
            .contentShape(Circle())
            .onHover { hovering = $0 }
    }
}

extension View {
    fileprivate func menuIconHover() -> some View {
        modifier(MenuIconHover())
    }
}
