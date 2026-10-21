//===----------------------------------------------------------------------===//
// SettingsView — app preferences.
//===----------------------------------------------------------------------===//

import SwiftUI
import AppKit
import ServiceManagement
import ContainerBackend

/// App settings: polling cadence, CLI path, runtime info, and storage cleanup.
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @AppStorage("appTheme") private var appTheme = AppTheme.system
    @AppStorage("pollInterval") private var pollInterval = 4.0
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("menuBarConfig") private var menuBarConfig = MenuBarConfig()
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @State private var launchAtLoginError: String?

    @State private var confirmPruneAll = false
    @State private var confirmBuilder = false
    @State private var confirmFull = false
    @State private var confirmInstall = false
    @State private var confirmInstallApp = false
    @State private var storageSizes: [(name: String, bytes: UInt64)] = []
    @State private var storageRedirected = false
    @State private var storageHasBackup = false
    @State private var pendingStorageParent: URL?
    @State private var confirmDeleteBackup = false
    @State private var confirmRuntimeUpgrade = false

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            runtime
                .tabItem { Label("Runtime", systemImage: "shippingbox") }
            storage
                .tabItem { Label("Storage", systemImage: "externaldrive") }
            menubar
                .tabItem { Label("Menu bar", systemImage: "menubar.rectangle") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var general: some View {
        ScrollView {
            Form {
            Section("Appearance") {
                Picker("Theme", selection: $appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Polling") {
                HStack {
                    Text("Refresh interval")
                    Spacer()
                    Picker("", selection: $pollInterval) {
                        Text("2s").tag(2.0)
                        Text("4s").tag(4.0)
                        Text("8s").tag(8.0)
                        Text("15s").tag(15.0)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            }
            Section("Startup") {
                Toggle("Start with system (login)", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            launchAtLoginError = nil
                        } catch {
                            launchAtLoginError = error.localizedDescription
                        }
                    }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section("Menu bar") {
                Toggle("Show menu bar extra", isOn: $showMenuBar)
            }
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Installation") {
                Button("Install app in /Applications") {
                    confirmInstallApp = true
                }
                .disabled(state.isInstallingApp)
                .confirmationDialog(
                    "Install app?",
                    isPresented: $confirmInstallApp,
                    titleVisibility: .visible
                ) {
                    Button("Install app", role: .destructive) {
                        Task { @MainActor in await state.installApp() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Copies Macker into /Applications so it can be launched from Launchpad or Spotlight. You will be asked for your administrator password.")
                }
                if state.isInstallingApp {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Installing...")
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Install CLI (replace docker commands)") {
                    confirmInstall = true
                }
                .disabled(state.isInstalling)
                .confirmationDialog(
                    "Install CLI?",
                    isPresented: $confirmInstall,
                    titleVisibility: .visible
                ) {
                    Button("Install CLI", role: .destructive) {
                        Task { @MainActor in await state.installCLI() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Installs macker to /usr/local/bin and symlinks it as `docker` and `docker-compose`, replacing any existing Docker CLI. You will be asked for your administrator password.")
                }
                if state.isInstalling {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Installing...")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        }
    }

    private var runtime: some View {
        ScrollView {
            Form {
            runtimeVersionSection
            Section("Daemon") {
                HStack {
                    Text("Status")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(state.isDaemonRunning ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(state.isDaemonRunning ? "Running" : "Unreachable")
                            .foregroundStyle(.secondary)
                    }
                }
                if let errorMessage = state.errorMessage {
                    HStack {
                        Text("Last error")
                        Spacer()
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            Section("Resources") {
                HStack {
                    Text("Containers")
                    Spacer()
                    Text("\(state.runningCount) / \(state.containers.count) running")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Images")
                    Spacer()
                    Text("\(state.images.count)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Volumes")
                    Spacer()
                    Text("\(state.volumes.count)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Networks")
                    Spacer()
                    Text("\(state.networks.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        }
    }

    /// Installed vs recommended vs latest apple/container, with a one-click upgrade.
    private var runtimeVersionSection: some View {
        let recommended = RuntimeVersion.recommended
        let installed = state.runtimeInstalled
        let upgradeNeeded = installed.map { RuntimeVersion.isOlder($0, than: recommended) } ?? true
        let latestUntested = state.runtimeLatest.map { RuntimeVersion.isOlder(recommended, than: $0) } ?? false

        return Section("Container runtime") {
            HStack {
                Text("Installed")
                Spacer()
                Text(installed ?? "Not found")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Recommended")
                Spacer()
                Text(recommended)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Latest")
                Spacer()
                if state.isCheckingRuntime {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(state.runtimeLatest ?? "Unknown")
                        .foregroundStyle(.secondary)
                }
            }
            if let runtimeLatestError = state.runtimeLatestError {
                Text(runtimeLatestError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if installed == recommended {
                Text("Up to date with the version Macker is tested against.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if installed != nil, !upgradeNeeded {
                Text("Installed version is newer than the one Macker is tested against.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if latestUntested {
                Text("Latest release is newer than what Macker supports yet. Upgrade stays on \(recommended).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Check for updates") {
                    Task { @MainActor in await state.checkRuntimeVersions() }
                }
                .disabled(state.isCheckingRuntime || state.isUpgradingRuntime)
                Spacer()
                if upgradeNeeded {
                    Button(installed == nil ? "Install \(recommended)" : "Upgrade to \(recommended)") {
                        confirmRuntimeUpgrade = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isUpgradingRuntime)
                }
            }
            if state.isUpgradingRuntime {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Updating runtime. The daemon restarts afterwards.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task { await state.checkRuntimeVersions() }
        .confirmationDialog(
            installed == nil ? "Install container \(recommended)?" : "Upgrade container to \(recommended)?",
            isPresented: $confirmRuntimeUpgrade,
            titleVisibility: .visible
        ) {
            Button(installed == nil ? "Install" : "Upgrade") {
                Task { @MainActor in await state.upgradeRuntime() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Downloads Apple's signed installer for container \(recommended), verifies its SHA-256 checksum, and installs it. The container daemon is stopped during the install and started again afterwards. You will be asked for your administrator password.")
        }
    }

    /// Where the runtime keeps its data, with a move action.
    private var storageLocation: some View {
        Section("Location") {
            HStack {
                Text("Current")
                Spacer()
                Text(StorageLocation.standard.resolvedRoot.path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if storageRedirected {
                Text("This folder is a link to another disk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(storageSizes, id: \.name) { folder in
                HStack {
                    Text(folder.name)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.formatBytes(folder.bytes))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            if storageHasBackup {
                HStack {
                    Text("The original data is kept as a backup until you delete it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Delete backup…", role: .destructive) {
                        confirmDeleteBackup = true
                    }
                    .disabled(state.isMovingStorage)
                }
            }
            HStack {
                Button("Move storage…") {
                    chooseStorageFolder()
                }
                .disabled(state.isMovingStorage)
                if state.isMovingStorage {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            if let message = state.storageMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(message.hasPrefix("Move failed") ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: reloadStorageInfo)
        .onChange(of: state.isMovingStorage) { _, moving in
            if !moving { reloadStorageInfo() }
        }
        .confirmationDialog(
            "Move the container storage?",
            isPresented: Binding(
                get: { pendingStorageParent != nil },
                set: { if !$0 { pendingStorageParent = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move storage") {
                guard let parent = pendingStorageParent else { return }
                pendingStorageParent = nil
                Task { @MainActor in
                    await state.moveStorage(toParent: parent)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingStorageParent = nil
            }
        } message: {
            Text("Images, containers, volumes and the build cache are copied to \(pendingStorageParent?.path ?? "the chosen folder"). Running containers are stopped during the move. The original stays as a backup until you delete it.")
        }
        .confirmationDialog(
            "Delete the backup?",
            isPresented: $confirmDeleteBackup,
            titleVisibility: .visible
        ) {
            Button("Delete backup", role: .destructive) {
                state.deleteStorageBackup()
                reloadStorageInfo()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only do this after checking that images and containers work from the new location.")
        }
    }

    private func reloadStorageInfo() {
        let location = StorageLocation.standard
        storageRedirected = location.isRedirected
        storageHasBackup = location.backup != nil
        storageSizes = location.sizes()
    }

    /// Lets the user pick a parent folder, then asks for confirmation.
    private func chooseStorageFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder where the container storage should live."
        if panel.runModal() == .OK, let url = panel.url {
            pendingStorageParent = url
        }
    }

    private var storage: some View {
        ScrollView {
            Form {
            storageLocation
            Section("Disk usage") {
                HStack {
                    Text("Total")
                    Spacer()
                    Text(state.diskUsage.totalSize.map(Self.formatBytes) ?? "-")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Images (incl. build cache)")
                    Spacer()
                    Text(state.diskUsage.imagesSize.map(Self.formatBytes) ?? "-")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Containers")
                    Spacer()
                    Text(state.diskUsage.containersSize.map(Self.formatBytes) ?? "-")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Volumes")
                    Spacer()
                    Text(state.diskUsage.volumesSize.map(Self.formatBytes) ?? "-")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Reclaimable")
                    Spacer()
                    Text(state.diskUsage.reclaimableSize.map(Self.formatBytes) ?? "-")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Cleanup") {
                Button("Prune unused images") {
                    Task { @MainActor in await state.pruneImages(all: false) }
                }
                .disabled(state.isCleaning)

                Button("Prune all images") {
                    confirmPruneAll = true
                }
                .disabled(state.isCleaning)
                .confirmationDialog(
                    "Prune all images?",
                    isPresented: $confirmPruneAll,
                    titleVisibility: .visible
                ) {
                    Button("Prune all images", role: .destructive) {
                        Task { @MainActor in await state.pruneImages(all: true) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes ALL images, including ones currently in use. The buildkit builder cache is not affected.")
                }

                Button("Delete buildkit builder") {
                    confirmBuilder = true
                }
                .disabled(state.isCleaning)
                .confirmationDialog(
                    "Delete buildkit builder?",
                    isPresented: $confirmBuilder,
                    titleVisibility: .visible
                ) {
                    Button("Delete buildkit builder", role: .destructive) {
                        Task { @MainActor in await state.deleteBuildkitBuilder() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The buildkit builder holds the build cache (snapshots from `container build`), which can consume tens of GB. It is recreated on the next build.")
                }

                Button("Full cleanup") {
                    confirmFull = true
                }
                .disabled(state.isCleaning)
                .confirmationDialog(
                    "Full cleanup?",
                    isPresented: $confirmFull,
                    titleVisibility: .visible
                ) {
                    Button("Full cleanup", role: .destructive) {
                        Task { @MainActor in await state.fullCleanup() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Deletes the buildkit builder and prunes ALL images. This reclaims the most space.")
                }
            }
            if state.isCleaning {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Cleaning up...")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        }
    }

    private var menubar: some View {
        Form {
            Section("Visibility") {
                Toggle("Show menu bar extra", isOn: $showMenuBar)
            }
            Section("Container list") {
                HStack {
                    Text("Max containers in list")
                    Spacer()
                    Stepper("\(menuBarConfig.maxContainers)",
                            value: $menuBarConfig.maxContainers, in: 0...20)
                }
            }
            Section {
                MenuBarItemsPicker(config: $menuBarConfig)
            } header: {
                Text("Items")
            } footer: {
                Text("Move items between the columns to enable or hide them. Use the arrows or drag to reorder the active items.")
            }
        }
        .formStyle(.grouped)
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// A two-column picker for the menu bar items: available (inactive) on the
/// left, active (ordered) on the right. Items move between columns with the
/// chevron buttons or by dragging, and the active column can be reordered with
/// the up/down arrows or by dragging.
private struct MenuBarItemsPicker: View {
    @Binding var config: MenuBarConfig
    @State private var availableSelection: MenuBarItem?
    @State private var activeSelection: MenuBarItem?

    private var available: [MenuBarItem] {
        MenuBarItem.allCases.filter { !config.activeItems.contains($0) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Available (inactive) column
            VStack(alignment: .leading, spacing: 4) {
                Text("Available")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                List(available, selection: $availableSelection) { item in
                    Label(item.label, systemImage: item.systemImage)
                        .tag(item)
                        .draggable(item)
                }
                .listStyle(.bordered)
                .frame(minHeight: 200)
                .dropDestination(for: MenuBarItem.self) { items, _ in
                    for item in items {
                        config.activeItems.removeAll { $0 == item }
                    }
                    return true
                }
            }

            // Middle controls
            VStack(spacing: 8) {
                Button {
                    if let item = availableSelection {
                        config.activeItems.append(item)
                        availableSelection = nil
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(availableSelection == nil)
                .help("Add selected item")

                Button {
                    if let item = activeSelection {
                        config.activeItems.removeAll { $0 == item }
                        activeSelection = nil
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(activeSelection == nil)
                .help("Remove selected item")

                Divider().frame(width: 20)

                Button {
                    moveActive(-1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(!canMoveActive(-1))
                .help("Move up")

                Button {
                    moveActive(1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(!canMoveActive(1))
                .help("Move down")
            }
            .buttonStyle(.bordered)
            .padding(.top, 18)

            // Active (ordered) column
            VStack(alignment: .leading, spacing: 4) {
                Text("Active")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                List(config.activeItems, selection: $activeSelection) { item in
                    Label(item.label, systemImage: item.systemImage)
                        .tag(item)
                        .draggable(item)
                }
                .listStyle(.bordered)
                .frame(minHeight: 200)
                .dropDestination(for: MenuBarItem.self) { items, _ in
                    for item in items {
                        config.activeItems.removeAll { $0 == item }
                        config.activeItems.append(item)
                    }
                    return true
                }
            }
        }
    }

    private func canMoveActive(_ offset: Int) -> Bool {
        guard let sel = activeSelection,
              let idx = config.activeItems.firstIndex(of: sel) else { return false }
        let newIdx = idx + offset
        return newIdx >= 0 && newIdx < config.activeItems.count
    }

    private func moveActive(_ offset: Int) {
        guard let sel = activeSelection,
              let idx = config.activeItems.firstIndex(of: sel) else { return }
        let newIdx = idx + offset
        guard newIdx >= 0 && newIdx < config.activeItems.count else { return }
        config.activeItems.remove(at: idx)
        config.activeItems.insert(sel, at: newIdx)
    }
}
