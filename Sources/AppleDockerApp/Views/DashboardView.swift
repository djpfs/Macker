//===----------------------------------------------------------------------===//
// DashboardView — resource overview + quick actions.
//===----------------------------------------------------------------------===//

import SwiftUI
import ContainerBackend

/// The landing screen: daemon status, resource usage, and quick actions.
struct DashboardView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                resourceCards
                DashboardChartsView()
                recentContainers
            }
            .padding(20)
        }
        .navigationTitle("Dashboard")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Macker")
                    .font(.largeTitle.bold())
                HStack(spacing: 8) {
                    Circle()
                        .fill(state.isDaemonRunning ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(state.isDaemonRunning ? "Runtime running" : "Runtime unreachable")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if state.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var resourceCards: some View {
        HStack(spacing: 16) {
            ResourceCard(
                title: "Containers",
                value: "\(state.runningCount) / \(state.containers.count)",
                subtitle: "running / total",
                systemImage: "shippingbox",
                color: .blue
            )
            ResourceCard(
                title: "Images",
                value: "\(state.images.count)",
                subtitle: "stored locally",
                systemImage: "photo.on.rectangle",
                color: .purple
            )
            ResourceCard(
                title: "Volumes",
                value: "\(state.volumes.count)",
                subtitle: "named volumes",
                systemImage: "externaldrive",
                color: .orange
            )
            ResourceCard(
                title: "Networks",
                value: "\(state.networks.count)",
                subtitle: "networks",
                systemImage: "network",
                color: .teal
            )
        }
    }

    private var recentContainers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Containers")
                .font(.headline)
            if state.containers.isEmpty {
                EmptyStateView(
                    systemImage: "shippingbox",
                    title: "No containers",
                    message: "Run a container from the Containers tab, or use `docker run` from the CLI."
                )
                .frame(height: 200)
            } else {
                Table(state.containers) {
                    TableColumn("Name") { container in
                        Text(container.id)
                    }
                    TableColumn("Image") { container in
                        Text(container.configuration.image.reference)
                    }
                    TableColumn("Status") { container in
                        StatusBadge(status: container.status)
                    }
                }
                .frame(minHeight: 200)
            }
        }
    }
}

/// A compact stat card used on the dashboard.
struct ResourceCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title2.bold())
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
        )
    }
}
