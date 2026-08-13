//===----------------------------------------------------------------------===//
// AppleDockerApp — SwiftUI application entry point (GUI mode).
//===----------------------------------------------------------------------===//

import SwiftUI
import AppKit
import ContainerBackend

/// The main-window sidebar sections. Top-level so AppState can tag running
/// operations with the section that owns them.
enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case containers = "Containers"
    case images = "Images"
    case builds = "Builds"
    case volumes = "Volumes"
    case networks = "Networks"
    case compose = "Compose"
    case activity = "Activity Monitor"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: "gauge"
        case .containers: "shippingbox"
        case .images: "photo.on.rectangle"
        case .builds: "hammer"
        case .volumes: "externaldrive"
        case .networks: "network"
        case .compose: "square.stack.3d.up"
        case .activity: "waveform.path.ecg"
        case .settings: "gearshape"
        }
    }
}

public struct AppleDockerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState()
    @AppStorage("showMenuBar") private var showMenuBar = true

    public init() {}

    public var body: some Scene {
        // A single-instance Window scene: "Open Macker" focuses the
        // existing window instead of spawning a new one.
        Window("Macker", id: "main") {
            RootView()
                .environment(state)
                .frame(minWidth: 1000, minHeight: 640)
                .task { state.startPolling() }
                .onDisappear { state.stopPolling() }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Macker") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
        }

        MenuBarExtra("Macker", systemImage: "shippingbox") {
            MenuBarView()
                .environment(state)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Keeps the app a regular (Dock + Cmd+Tab) app even though it has a
/// MenuBarExtra scene. SwiftUI would otherwise force `.accessory` activation
/// policy, which removes the app from Cmd+Tab and makes its window hide when
/// clicked. Setting the policy here (after launch) overrides that.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Use the same SF Symbol shown in the menu bar as the app icon.
        if let symbol = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: "Macker") {
            let config = NSImage.SymbolConfiguration(pointSize: 128, weight: .regular)
            if let large = symbol.withSymbolConfiguration(config) {
                NSApp.applicationIconImage = large
            } else {
                NSApp.applicationIconImage = symbol
            }
        }
    }
}

/// The main window: sidebar navigation + detail pane.
private struct RootView: View {
    @Environment(AppState.self) private var state
    @State private var selection: SidebarItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                sidebarRow(item)
                    .tag(item)
            }
            .navigationTitle("Macker")
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 360)
            .safeAreaInset(edge: .bottom) {
                daemonStatus
            }
        } detail: {
            switch selection {
            case .dashboard:
                DashboardView()
            case .containers:
                ContainerListView()
            case .images:
                ImageListView()
            case .builds:
                BuildsView()
            case .volumes:
                VolumeListView()
            case .networks:
                NetworkListView()
            case .compose:
                ComposeView()
            case .activity:
                ActivityMonitorView()
            case .settings:
                SettingsView()
            case nil:
                EmptyStateView(
                    systemImage: "shippingbox",
                    title: "Macker",
                    message: "Select a section from the sidebar."
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                operationsIndicator
            }
        }
    }

    /// A sidebar row with a green dot when the section has running operations.
    private func sidebarRow(_ item: SidebarItem) -> some View {
        HStack(spacing: 6) {
            Label(item.rawValue, systemImage: item.systemImage)
            if state.hasActiveOperation(in: item) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Running operations")
            }
        }
    }

    /// Toolbar button that surfaces all background operations in a popover.
    private var operationsIndicator: some View {
        let count = state.operations.count
        return Menu {
            if count == 0 {
                Text("No operations running")
                    .font(.callout)
            } else {
                ForEach(state.operations) { op in
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(op.title)
                            if let section = op.section {
                                Text(section.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                if count > 0 {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "terminal")
                }
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.bold())
                }
            }
            .padding(.horizontal, 4)
        }
        .help(count > 0 ? "\(count) operation(s) running" : "No operations running")
    }

    private var daemonStatus: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.isDaemonRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(state.isDaemonRunning ? "Runtime running" : "Runtime unreachable")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .background(.bar)
    }
}
