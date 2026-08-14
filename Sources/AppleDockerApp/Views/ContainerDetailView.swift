//===----------------------------------------------------------------------===//
// ContainerDetailView — info, live stats, and streaming logs for a container.
//===----------------------------------------------------------------------===//

import SwiftUI
import ContainerBackend

/// Detail pane for a single container.
struct ContainerDetailView: View {
    @Environment(AppState.self) private var state
    let container: ContainerSnapshot
    @State private var selectedTab = "Info"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("", selection: $selectedTab) {
                Text("Info").tag("Info")
                Text("Stats").tag("Stats")
                Text("Logs").tag("Logs")
                Text("Files").tag("Files")
                Text("Terminal").tag("Terminal")
                Text("Settings").tag("Settings")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            switch selectedTab {
            case "Stats":
                StatsView(container: container)
            case "Logs":
                LogsView(containerID: container.id)
            case "Files":
                ContainerFilesView(containerID: container.id)
            case "Terminal":
                ContainerTerminalView(containerID: container.id)
            case "Settings":
                ContainerSettingsView(container: container)
            default:
                InfoView(container: container)
            }
        }
        .navigationTitle(container.id)
    }

    private var header: some View {
        HStack(spacing: 12) {
            StatusDot(status: container.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(container.id)
                    .font(.title2.bold())
                Text(container.configuration.image.reference)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(status: container.status)
            if container.status == .running {
                Button {
                    Task { @MainActor in await state.stopContainer(container.id) }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    Task { @MainActor in await state.startContainer(container.id) }
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            Button {
                Task { @MainActor in await state.showContainerInFinder(container.id) }
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .help("Export the container filesystem and reveal it in Finder")
            Button(role: .destructive) {
                Task { @MainActor in await state.deleteContainer(container.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
    }
}

/// The Info tab: configuration details.
private struct InfoView: View {
    let container: ContainerSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("Configuration") {
                    infoRow("ID", container.id)
                    infoRow("Image", container.configuration.image.reference)
                    infoRow("Status", container.status.rawValue)
                    infoRow("Created", container.configuration.creationDate.formatted())
                }
                if !container.configuration.publishedPorts.isEmpty {
                    section("Ports") {
                        ForEach(container.configuration.publishedPorts, id: \.containerPort) { port in
                            infoRow("\(port.containerPort)/\(port.proto.rawValue)",
                                    "\(port.hostAddress):\(port.hostPort)")
                        }
                    }
                }
                if !container.configuration.mounts.isEmpty {
                    section("Mounts") {
                        ForEach(container.configuration.mounts, id: \.destination) { mount in
                            infoRow(mount.destination, mount.source)
                        }
                    }
                }
                if !container.configuration.labels.isEmpty {
                    section("Labels") {
                        ForEach(container.configuration.labels.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            infoRow(key, value)
                        }
                    }
                }
                section("Security") {
                    infoRow("Privileged", container.configuration.privileged ? "Yes" : "No")
                    infoRow("Read-only rootfs", container.configuration.readOnly ? "Yes" : "No")
                    if !container.configuration.capAdd.isEmpty {
                        infoRow("Capabilities +", container.configuration.capAdd.joined(separator: ", "))
                    }
                    if !container.configuration.capDrop.isEmpty {
                        infoRow("Capabilities -", container.configuration.capDrop.joined(separator: ", "))
                    }
                    if !container.configuration.securityOptions.isEmpty {
                        infoRow("Security options", container.configuration.securityOptions.joined(separator: ", "))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer()
        }
        .font(.callout)
    }
}

/// The Stats tab: live CPU/memory gauges.
private struct StatsView: View {
    @Environment(AppState.self) private var state
    let container: ContainerSnapshot

    var body: some View {
        let stat = state.stats[container.id]
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 20) {
                Gauge(value: cpuPercent, in: 0...100) {
                    Text("CPU")
                } currentValueLabel: {
                    Text(String(format: "%.1f%%", cpuPercent))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(.blue)

                Gauge(value: memoryPercent, in: 0...1) {
                    Text("Memory")
                } currentValueLabel: {
                    Text(String(format: "%.0f%%", memoryPercent * 100))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(.orange)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 20)

            VStack(alignment: .leading, spacing: 8) {
                Text("Memory")
                    .font(.headline)
                Text("\(formatBytes(stat?.memoryUsageBytes ?? 0)) / \(formatBytes(stat?.memoryLimitBytes ?? 0))")
                    .font(.callout)
                Text("CPU: \(String(format: "%.2f", cpuPercent))%")
                    .font(.callout)
                Text("Network: \(formatBytes(stat?.networkRxBytes ?? 0)) ↓ / \(formatBytes(stat?.networkTxBytes ?? 0)) ↑")
                    .font(.callout)
                Text("Block I/O: \(formatBytes(stat?.blockReadBytes ?? 0)) / \(formatBytes(stat?.blockWriteBytes ?? 0))")
                    .font(.callout)
                Text("Processes: \(stat?.numProcesses.map(String.init) ?? "-")")
                    .font(.callout)
            }
            .padding(20)
            Spacer()
        }
    }

    private var cpuPercent: Double {
        guard let usec = state.stats[container.id]?.cpuUsageUsec else { return 0 }
        return min(Double(usec) / 1_000_000, 100)
    }

    private var memoryPercent: Double {
        guard let used = state.stats[container.id]?.memoryUsageBytes,
              let limit = state.stats[container.id]?.memoryLimitBytes, limit > 0 else { return 0 }
        return min(Double(used) / Double(limit), 1)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// The Logs tab: streaming container logs.
private struct LogsView: View {
    let containerID: String
    @AppStorage("logTail") private var tail = 100
    @State private var lines: [String] = []
    @State private var follow = true
    @State private var task: Task<Void, Never>?

    var body: some View {
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
        .safeAreaInset(edge: .bottom) {
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
            .padding(8)
            .background(.bar)
        }
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
