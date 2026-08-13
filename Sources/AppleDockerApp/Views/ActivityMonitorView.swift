//===----------------------------------------------------------------------===//
// ActivityMonitorView — system-wide resource usage across all containers.
//
// OrbStack-style Activity Monitor: overall CPU/memory/network/disk gauges plus
// a per-container breakdown table.
//===----------------------------------------------------------------------===//

import SwiftUI
import ContainerBackend

/// The Activity Monitor tab: aggregate resource usage and per-container stats.
struct ActivityMonitorView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryCards
                Divider()
                perContainerTable
            }
            .padding(20)
        }
        .navigationTitle("Activity Monitor")
    }

    private var runningContainers: [ContainerSnapshot] {
        state.containers.filter { $0.status == .running }
    }

    private var summaryCards: some View {
        // Use a wrapping grid so the cards never get cut off when the detail
        // pane is narrow.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
            metricCard(
                title: "CPU",
                value: String(format: "%.1f%%", state.totalCPUPercent),
                systemImage: "cpu",
                color: .blue
            )
            metricCard(
                title: "Memory",
                value: "\(formatBytes(state.totalMemoryBytes)) / \(formatBytes(state.totalMemoryLimitBytes))",
                systemImage: "memorychip",
                color: .orange
            )
            metricCard(
                title: "Containers",
                value: "\(state.runningCount) running",
                systemImage: "shippingbox",
                color: .green
            )
            metricCard(
                title: "Network",
                value: "\(formatBytes(totalNetworkRx)) ↓ / \(formatBytes(totalNetworkTx)) ↑",
                systemImage: "network",
                color: .purple
            )
        }
    }

    private func metricCard(title: String, value: String, systemImage: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var totalNetworkRx: UInt64 {
        runningContainers.reduce(0) { $0 + (state.stats[$1.id]?.networkRxBytes ?? 0) }
    }

    private var totalNetworkTx: UInt64 {
        runningContainers.reduce(0) { $0 + (state.stats[$1.id]?.networkTxBytes ?? 0) }
    }

    private var perContainerTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Containers")
                .font(.headline)

            if runningContainers.isEmpty {
                Text("No running containers")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Table(runningContainers) {
                    TableColumn("Name") { container in
                        HStack(spacing: 6) {
                            StatusDot(status: container.status)
                            Text(container.id)
                        }
                    }
                    TableColumn("CPU") { container in
                        Text(String(format: "%.1f%%", cpuPercent(container)))
                    }
                    TableColumn("Memory") { container in
                        Text(formatBytes(state.stats[container.id]?.memoryUsageBytes ?? 0))
                    }
                    TableColumn("Network ↓") { container in
                        Text(formatBytes(state.stats[container.id]?.networkRxBytes ?? 0))
                    }
                    TableColumn("Network ↑") { container in
                        Text(formatBytes(state.stats[container.id]?.networkTxBytes ?? 0))
                    }
                    TableColumn("Disk I/O") { container in
                        Text("\(formatBytes(state.stats[container.id]?.blockReadBytes ?? 0)) / \(formatBytes(state.stats[container.id]?.blockWriteBytes ?? 0))")
                    }
                    TableColumn("Processes") { container in
                        Text(state.stats[container.id]?.numProcesses.map(String.init) ?? "-")
                    }
                }
                .frame(minHeight: 200)
            }
        }
    }

    private func cpuPercent(_ container: ContainerSnapshot) -> Double {
        guard let usec = state.stats[container.id]?.cpuUsageUsec else { return 0 }
        return min(Double(usec) / 1_000_000, 100)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
