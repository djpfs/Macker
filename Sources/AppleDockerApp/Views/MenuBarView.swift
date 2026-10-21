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
        VStack(alignment: .leading, spacing: 12) {
            header

            if config.hasMetrics {
                metrics
            }

            if config.activeItems.contains(.containerList) {
                containerSection
            }

            Divider()
            footer
        }
        .padding(12)
        .frame(width: 320)
        .sheet(item: $logsRequest) { request in
            LogsSheet(containerID: request.id)
        }
    }

    // MARK: - Header

    /// Title, runtime state and the actions menu, in one row.
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Macker")
                    .font(.headline)
                HStack(spacing: 5) {
                    Circle()
                        .fill(state.isDaemonRunning ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                    Text(state.isDaemonRunning ? "Runtime running" : "Runtime unreachable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if config.activeItems.contains(.actions) {
                Menu {
                    runtimeMenu
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Runtime actions")
            }
        }
    }

    // MARK: - Metrics

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if config.activeItems.contains(.cpuRing) {
                    ringCard(
                        value: state.totalCPUPercent / 100,
                        title: "CPU",
                        detail: String(format: "%.1f%%", state.totalCPUPercent),
                        color: .blue
                    )
                }
                if config.activeItems.contains(.memoryRing) {
                    ringCard(
                        value: state.totalMemoryLimitBytes > 0
                            ? Double(state.totalMemoryBytes) / Double(state.totalMemoryLimitBytes)
                            : 0,
                        title: "Memory",
                        detail: formatBytes(state.totalMemoryBytes),
                        color: .orange
                    )
                }
            }

            if !textMetrics.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(textMetrics, id: \.label) { metric in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(metric.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(metric.value)
                                .font(.callout.weight(.semibold))
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
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

    private var containerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Containers")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(state.runningCount) of \(state.containers.count) running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if state.containers.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "shippingbox")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No containers yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            } else {
                containerList
            }
        }
    }

    private var containerList: some View {
        ForEach(containerGroups) { group in
            VStack(alignment: .leading, spacing: 2) {
                if group.containers.count > 1 || group.title != group.containers.first?.id {
                    Text(group.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.top, 4)
                }

                ForEach(group.containers.prefix(config.maxContainers)) { container in
                    containerRow(container)
                }
            }
        }
    }

    private func containerRow(_ container: ContainerSnapshot) -> some View {
        HStack(spacing: 8) {
            StatusDot(status: container.status)
            VStack(alignment: .leading, spacing: 1) {
                Text(container.id)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(container.configuration.image.reference)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
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
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .menuHover()
    }

    // MARK: - Actions

    /// Runtime and app commands, shared by the header menu and the footer.
    private var runtimeMenu: some View {
        Group {
            Button("Refresh") {
                Task { @MainActor in await state.refresh() }
            }

            Divider()

            Button("Stop runtime") {
                Task { @MainActor in await state.stopDaemon() }
            }
            .disabled(!state.isDaemonRunning)

            Button("Restart runtime") {
                Task { @MainActor in await state.restartDaemon() }
            }

            Button("Prune build cache") {
                Task { @MainActor in await state.deleteBuildkitBuilder() }
            }
            .help("Deletes the buildkit builder, freeing the build cache (can be tens of GB). Recreated on the next build.")

            Divider()

            Button("Reset menu bar layout") {
                config = MenuBarConfig()
            }

            Button("Quit Macker", role: .destructive) {
                NSApp.terminate(nil)
            }
        }
    }

    /// Footer: refresh and the open-window action, sized to sit under the list.
    private var footer: some View {
        HStack(spacing: 8) {
            if config.activeItems.contains(.refresh) {
                footerIcon("arrow.clockwise", "Refresh") {
                    Task { @MainActor in await state.refresh() }
                }
            }
            Spacer()
            Button {
                openWindow(id: "main")
            } label: {
                Label("Open Macker", systemImage: "macwindow")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    /// A small circular icon button used in the footer.
    private func footerIcon(_ systemImage: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .menuIconHover()
        .help(help)
    }

    /// A circular gauge with the value in the middle and a title and detail below.
    private func ringCard(value: Double, title: String, detail: String, color: Color) -> some View {
        let fraction = min(max(value, 0), 1)
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: fraction)
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            .frame(width: 56, height: 56)
            VStack(spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
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
                .contentBackground()
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
