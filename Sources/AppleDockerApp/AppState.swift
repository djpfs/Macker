//===----------------------------------------------------------------------===//
// AppState — central observable state for the GUI.
//
// Polls the runtime on a fixed cadence (containers/images/volumes/networks
// every 4s, per-container stats every 2s) and exposes the actions the views
// need. All mutations funnel through here so the GUI and CLI never drift.
//===----------------------------------------------------------------------===//

import Foundation
import AppKit
import Observation
import ContainerBackend
import ComposeEngine

/// A single point-in-time sample of per-container stats, used to build the
/// dashboard time-series charts.
struct StatsSample {
    let timestamp: Date
    let stats: [String: ContainerStats]
}

/// A single recorded image build, shown in the Builds tab.
struct BuildRecord: Identifiable, Codable {
    let id: UUID
    let reference: String
    let context: String
    let startedAt: Date
    var finishedAt: Date?
    var succeeded: Bool?
    var detail: String?

    init(
        id: UUID = UUID(),
        reference: String,
        context: String,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        succeeded: Bool? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.reference = reference
        self.context = context
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.succeeded = succeeded
        self.detail = detail
    }
}

/// The app's shared state, injected into the view hierarchy via the
/// environment. Main-actor isolated so views can touch it directly.
@MainActor
@Observable
final class AppState {
    // MARK: - Data

    /// All containers (running and stopped).
    var containers: [ContainerSnapshot] = []
    /// All images.
    var images: [ImageSummary] = []
    /// All volumes.
    var volumes: [VolumeConfiguration] = []
    /// All networks.
    var networks: [NetworkResource] = []
    /// Per-container stats, keyed by container ID.
    var stats: [String: ContainerStats] = [:]
    /// Whether the container daemon is reachable.
    var isDaemonRunning = false
    /// The last error surfaced to the UI, if any.
    var errorMessage: String?
    /// Whether a refresh is in flight (for the progress indicator).
    var isRefreshing = false
    /// System disk usage (total / reclaimable).
    var diskUsage = SystemDiskUsage()
    /// Whether a cleanup operation is in flight (disables the cleanup buttons).
    var isCleaning = false
    /// Whether a CLI install is in flight.
    var isInstalling = false
    /// Whether an app install into /Applications is in flight.
    var isInstallingApp = false
    /// Rolling history of per-container stats for the dashboard charts.
    var statsHistory: [StatsSample] = []
    /// History of image builds, shown in the Builds tab (most recent first).
    var buildHistory: [BuildRecord] = []
    /// Persistent terminal sessions, keyed by container ID. Kept here so the
    /// terminal survives tab switches.
    var terminalSessions: [String: ContainerTerminalSession] = [:]

    // MARK: - Build tracking

    /// Record a build in the Builds tab history (most recent first, capped).
    func recordBuild(_ reference: String, context: String) -> UUID {
        let record = BuildRecord(reference: reference, context: context, startedAt: Date())
        buildHistory.insert(record, at: 0)
        if buildHistory.count > 50 {
            buildHistory.removeLast(buildHistory.count - 50)
        }
        persistBuildHistory()
        return record.id
    }

    /// Mark a recorded build as finished with its outcome.
    func finishBuild(_ id: UUID, succeeded: Bool, detail: String? = nil) {
        guard let index = buildHistory.firstIndex(where: { $0.id == id }) else { return }
        buildHistory[index].finishedAt = Date()
        buildHistory[index].succeeded = succeeded
        buildHistory[index].detail = detail
        persistBuildHistory()
    }

    /// Clear the build history.
    func clearBuildHistory() {
        buildHistory = []
        UserDefaults.standard.removeObject(forKey: "buildHistory")
    }

    /// Persist the build history to UserDefaults so it survives app restarts.
    private func persistBuildHistory() {
        guard let data = try? JSONEncoder().encode(buildHistory) else { return }
        UserDefaults.standard.set(data, forKey: "buildHistory")
    }

    /// Restore the build history from UserDefaults.
    func loadBuildHistory() {
        guard let data = UserDefaults.standard.data(forKey: "buildHistory"),
              let decoded = try? JSONDecoder().decode([BuildRecord].self, from: data) else {
            return
        }
        buildHistory = decoded
    }

    /// Build an image from a context directory. Records the build in the
    /// Builds tab history and returns the captured output.
    func buildImage(
        context: String,
        tag: String? = nil,
        dockerfile: String? = nil,
        buildArgs: [String: String] = [:],
        noCache: Bool = false
    ) async -> String {
        let opID = beginOperation("build \(tag ?? context)", section: .images)
        defer { endOperation(opID) }
        let reference = tag ?? (context as NSString).lastPathComponent
        let recordID = recordBuild(reference, context: context)
        do {
            let output = try await service.buildImage(
                context: context,
                tag: tag,
                dockerfile: dockerfile,
                buildArgs: buildArgs,
                noCache: noCache
            )
            finishBuild(recordID, succeeded: true, detail: nil)
            return output
        } catch {
            finishBuild(recordID, succeeded: false, detail: error.localizedDescription)
            return error.localizedDescription
        }
    }

    // MARK: - Compose state (persists across tab switches)

    /// The currently loaded compose project.
    var composeProject: ComposeProject?
    /// The path of the currently loaded compose file.
    var composeFilePath: String?
    /// Recently used compose file paths (most recent first).
    var composeHistory: [String] = []
    /// Streaming log lines for the compose operations panel.
    var composeLogLines: [String] = []
    /// Whether the compose log panel is visible.
    var composeShowLogs = false
    /// The last compose status message.
    var composeStatusMessage: StatusMessage?

    // MARK: - Background operations

    /// All in-flight background operations, used for the sidebar green dots and
    /// the toolbar operations indicator.
    var operations: [RunningOperation] = []

    /// Whether any operation is currently running.
    var hasRunningOperations: Bool { !operations.isEmpty }

    /// Whether the given sidebar section has at least one running operation.
    func hasActiveOperation(in section: SidebarItem) -> Bool {
        operations.contains { $0.section == section }
    }

    /// Register a new background operation and return its id.
    @discardableResult
    func beginOperation(_ title: String, section: SidebarItem?) -> UUID {
        let op = RunningOperation(id: UUID(), title: title, section: section, startedAt: Date())
        operations.append(op)
        return op.id
    }

    /// Mark a background operation as finished and remove it from the list.
    func endOperation(_ id: UUID) {
        operations.removeAll { $0.id == id }
    }

    // MARK: - Derived

    /// Total CPU usage across running containers (seconds of CPU / wall time).
    var totalCPUPercent: Double {
        let running = containers.filter { $0.status == .running }
        guard !running.isEmpty else { return 0 }
        let sum = running.reduce(0.0) { $0 + (stats[$1.id]?.cpuUsageUsec.map { Double($0) } ?? 0) }
        return sum / 1_000_000
    }

    /// Total memory usage across running containers.
    var totalMemoryBytes: UInt64 {
        containers.filter { $0.status == .running }.reduce(0) {
            $0 + (stats[$1.id]?.memoryUsageBytes ?? 0)
        }
    }

    /// Total memory limit across running containers.
    var totalMemoryLimitBytes: UInt64 {
        containers.filter { $0.status == .running }.reduce(0) {
            $0 + (stats[$1.id]?.memoryLimitBytes ?? 0)
        }
    }

    /// Number of running containers.
    var runningCount: Int {
        containers.filter { $0.status == .running }.count
    }

    // MARK: - Internals

    private let service: ContainerService
    private var pollTask: Task<Void, Never>?

    /// Nonisolated because `service` is immutable — lets the `@State` initial
    /// value in the `App` struct be created from a nonisolated context.
    nonisolated init(service: ContainerService = ContainerService()) {
        self.service = service
    }

    // MARK: - Polling

    /// Start the background polling loop.
    func startPolling() {
        guard pollTask == nil else { return }
        loadComposeHistory()
        loadBuildHistory()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    /// Stop the background polling loop.
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Refresh all resource lists in one pass.
    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            async let containers = service.listContainers(filters: .all)
            async let images = service.images.list()
            async let volumes = service.listVolumes()
            async let networks = service.listNetworks()
            async let health = service.ping()
            async let diskUsage = service.systemDiskUsage()
            _ = try await health
            self.containers = try await containers
            self.images = try await images
            self.volumes = try await volumes
            self.networks = try await networks
            self.diskUsage = try await diskUsage
            isDaemonRunning = true
            errorMessage = nil
        } catch {
            isDaemonRunning = false
            errorMessage = error.localizedDescription
        }
        await refreshStats()
    }

    /// Refresh per-container stats for running containers and append a sample
    /// to the dashboard history (capped to the last 120 samples).
    func refreshStats() async {
        let running = containers.filter { $0.status == .running }
        var sample: [String: ContainerStats] = [:]
        for container in running {
            if let stat = try? await service.containerStats(id: container.id) {
                stats[container.id] = stat
                sample[container.id] = stat
            }
        }
        statsHistory.append(StatsSample(timestamp: Date(), stats: sample))
        if statsHistory.count > 120 {
            statsHistory.removeFirst(statsHistory.count - 120)
        }
    }


    // MARK: - Compose actions

    /// Load a compose file, parse it, and record it in the recent history.
    /// Returns the parsed project, or throws on parse/validation failure.
    @discardableResult
    func loadComposeFile(at path: String) throws -> ComposeProject {
        let parser = ComposeParser()
        let parsed = try parser.parse(fileAt: path)
        try parser.validate(parsed)
        composeProject = parsed
        composeFilePath = path
        composeStatusMessage = nil
        addComposeToHistory(path)
        return parsed
    }

    /// Record a compose file path in the recent history (most recent first,
    /// deduplicated, capped at 10 entries) and persist it.
    func addComposeToHistory(_ path: String) {
        composeHistory.removeAll { $0 == path }
        composeHistory.insert(path, at: 0)
        if composeHistory.count > 10 {
            composeHistory.removeLast(composeHistory.count - 10)
        }
        UserDefaults.standard.set(composeHistory, forKey: "composeHistory")
    }

    /// Restore the compose history from UserDefaults.
    func loadComposeHistory() {
        composeHistory = UserDefaults.standard.stringArray(forKey: "composeHistory") ?? []
    }

    /// Clear the compose history.
    func clearComposeHistory() {
        composeHistory = []
        UserDefaults.standard.removeObject(forKey: "composeHistory")
    }

    /// Append a line to the compose log panel.
    func appendComposeLog(_ line: String) {
        composeLogLines.append(line)
    }

    /// Clear the compose log panel.
    func clearComposeLog() {
        composeLogLines = []
    }


    // MARK: - Terminal sessions

    /// Return the persistent terminal session for a container, creating it on
    /// first use.
    func terminalSession(for containerID: String) -> ContainerTerminalSession {
        if let session = terminalSessions[containerID] {
            return session
        }
        let session = ContainerTerminalSession(containerID: containerID)
        terminalSessions[containerID] = session
        return session
    }

    // MARK: - Container actions

    func startContainer(_ id: String) async {
        let opID = beginOperation("startContainer", section: .containers)
        defer { endOperation(opID) }
        do {
            try await service.bootstrapContainer(id: id)
            try await service.startProcess(containerId: id, processId: id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopContainer(_ id: String) async {
        let opID = beginOperation("stopContainer", section: .containers)
        defer { endOperation(opID) }
        do {
            try await service.stopContainer(id: id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restartContainer(_ id: String) async {
        let opID = beginOperation("restartContainer", section: .containers)
        defer { endOperation(opID) }
        do {
            try await service.stopContainer(id: id)
            try await service.bootstrapContainer(id: id)
            try await service.startProcess(containerId: id, processId: id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func killContainer(_ id: String) async {
        let opID = beginOperation("killContainer", section: .containers)
        defer { endOperation(opID) }
        do {
            try await service.killContainer(id: id, signal: "SIGKILL")
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteContainer(_ id: String) async {
        let opID = beginOperation("deleteContainer", section: .containers)
        defer { endOperation(opID) }
        do {
            try await service.deleteContainer(id: id, force: true)
            stats[id] = nil
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Export a container's filesystem to a temporary folder and reveal it in
    /// Finder (OrbStack-style "Show in Finder"). The export is a full snapshot
    /// of the container's rootfs, extracted into a temp directory.
    func showContainerInFinder(_ id: String) async {
        let opID = beginOperation("Show in Finder", section: .containers)
        defer { endOperation(opID) }
        do {
            let fm = FileManager.default
            let dir = fm.temporaryDirectory
                .appendingPathComponent("macker-\(id)", isDirectory: true)
            try? fm.removeItem(at: dir)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)

            let archive = dir.appendingPathComponent("rootfs.tar")
            try await service.exportContainer(id: id, archive: archive)

            // Extract the archive into the folder so Finder shows the files.
            let extractDir = dir.appendingPathComponent("rootfs", isDirectory: true)
            try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xf", archive.path, "-C", extractDir.path]
            try process.run()
            process.waitUntilExit()

            NSWorkspace.shared.activateFileViewerSelecting([extractDir])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Recreate a container: stop, delete, then re-create from its stored
    /// configuration and start it again (like `docker compose up --force-recreate`).
    func recreateContainer(_ id: String) async {
        let opID = beginOperation("recreateContainer", section: .containers)
        defer { endOperation(opID) }
        guard let snapshot = containers.first(where: { $0.id == id }) else {
            errorMessage = "Container not found: \(id)"
            return
        }
        await recreate(id: id, configuration: snapshot.configuration, original: snapshot)
    }

    /// Apply a modified configuration to a container by recreating it: stop,
    /// delete, then re-create with the new configuration and start it again.
    /// Used by the container Settings tab (networks, ports, resources, env).
    func applyContainerConfig(_ id: String, configuration: ContainerConfiguration) async {
        let opID = beginOperation("applyContainerConfig", section: .containers)
        defer { endOperation(opID) }
        guard let original = containers.first(where: { $0.id == id }) else {
            errorMessage = "Container not found: \(id)"
            return
        }
        await recreate(id: id, configuration: configuration, original: original)
    }

    /// Shared recreation routine used by ``recreateContainer`` and
    /// ``applyContainerConfig``. Stops and deletes the container, then creates
    /// it again with `configuration` and starts it. If any step fails, the
    /// original container is restored from `original` so it never silently
    /// disappears (e.g. a compose container whose locally-built image can't be
    /// re-created).
    private func recreate(id: String, configuration: ContainerConfiguration, original: ContainerSnapshot) async {
        do {
            try await service.stopContainer(id: id)
            try await service.deleteContainer(id: id, force: true)
            stats[id] = nil
            try await service.createContainer(configuration: configuration)
            try await service.bootstrapContainer(id: id)
            try await service.startProcess(containerId: id, processId: id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            // Recreate failed — the container was already deleted. Restore the
            // original so the user doesn't lose it. If the new container was
            // partially created (create succeeded but bootstrap/start failed),
            // remove it first so the id is free for the restore.
            do {
                try? await service.deleteContainer(id: id, force: true)
                try await service.createContainer(configuration: original.configuration)
                try await service.bootstrapContainer(id: id)
                try await service.startProcess(containerId: id, processId: id)
                await refresh()
            } catch {
                errorMessage = "Apply failed: \(error.localizedDescription). Restore also failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Image actions

    func pullImage(_ reference: String) async {
        let opID = beginOperation("pullImage", section: .images)
        defer { endOperation(opID) }
        do {
            try await service.images.pull(reference)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteImage(_ reference: String) async {
        let opID = beginOperation("deleteImage", section: .images)
        defer { endOperation(opID) }
        do {
            try await service.images.delete([reference])
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Daemon actions

    /// Stop the container-apiserver daemon.
    func stopDaemon() async {
        let opID = beginOperation("stopDaemon", section: .dashboard)
        defer { endOperation(opID) }
        do {
            try await service.daemon.stop()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Restart the container-apiserver daemon (stop + start).
    func restartDaemon() async {
        let opID = beginOperation("restartDaemon", section: .dashboard)
        defer { endOperation(opID) }
        do {
            try await service.daemon.stop()
            try await service.daemon.start()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Cleanup actions

    /// Prune images. When `all` is true, removes ALL images (not just dangling).
    func pruneImages(all: Bool) async {
        let opID = beginOperation("pruneImages", section: .images)
        defer { endOperation(opID) }
        isCleaning = true
        defer { isCleaning = false }
        do {
            try await service.images.prune(all: all)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Delete the buildkit builder container (frees the build cache).
    func deleteBuildkitBuilder() async {
        let opID = beginOperation("deleteBuildkitBuilder", section: .images)
        defer { endOperation(opID) }
        isCleaning = true
        defer { isCleaning = false }
        do {
            try await service.deleteBuildkitBuilder()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Full cleanup: delete the buildkit builder and prune all images.
    func fullCleanup() async {
        let opID = beginOperation("fullCleanup", section: .images)
        defer { endOperation(opID) }
        isCleaning = true
        defer { isCleaning = false }
        do {
            try await service.deleteBuildkitBuilder()
            try await service.images.prune(all: true)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Install the CLI into /usr/local/bin and symlink it as `docker` and
    /// `docker-compose`, replacing any existing Docker CLI. Uses `osascript`
    /// with administrator privileges so the user is prompted for their
    /// password (the same way `make install` needs `sudo`).
    func installCLI() async {
        let opID = beginOperation("installCLI", section: .settings)
        defer { endOperation(opID) }
        guard !isInstalling else { return }
        isInstalling = true
        defer { isInstalling = false }

        let binary = Bundle.main.executablePath ?? "/usr/local/bin/macker"
        let script = """
        install -d /usr/local/bin
        install -m 0755 "\(binary)" /usr/local/bin/macker
        ln -sf /usr/local/bin/macker /usr/local/bin/docker
        ln -sf /usr/local/bin/macker /usr/local/bin/docker-compose
        """
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let osa = "do shell script \"\(escaped)\" with administrator privileges"

        do {
            let runner = ProcessRunner(containerPath: "/usr/bin/osascript")
            let result = try await runner.runExecutable(
                "/usr/bin/osascript",
                args: ["-e", osa],
                timeout: .seconds(120)
            )
            if result.succeeded {
                errorMessage = nil
            } else {
                errorMessage = result.stderr.isEmpty ? "Install failed (exit \(result.exitCode))" : result.stderr
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Install the app bundle into /Applications so it can be launched from
    /// Launchpad / Spotlight like a normal macOS app. Builds a minimal .app
    /// bundle around the current executable and copies it into /Applications.
    /// Uses `osascript` with administrator privileges for the password prompt.
    func installApp() async {
        let opID = beginOperation("installApp", section: .settings)
        defer { endOperation(opID) }
        guard !isInstallingApp else { return }
        isInstallingApp = true
        defer { isInstallingApp = false }

        let binary = Bundle.main.executablePath ?? "/usr/local/bin/macker"
        let appName = "Macker"
        let appPath = "/Applications/\(appName).app"
        let execName = "macker"

        // Minimal Info.plist so Launchpad/Spotlight can index the app.
        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleName</key><string>\(appName)</string>
            <key>CFBundleDisplayName</key><string>\(appName)</string>
            <key>CFBundleIdentifier</key><string>com.macker.app</string>
            <key>CFBundleExecutable</key><string>\(execName)</string>
            <key>CFBundlePackageType</key><string>APPL</string>
            <key>CFBundleShortVersionString</key><string>1.0.0</string>
            <key>CFBundleVersion</key><string>1</string>
            <key>LSMinimumSystemVersion</key><string>15.0</string>
            <key>NSHighResolutionCapable</key><true/>
            <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
        </dict>
        </plist>
        """

        let script = """
        set -e
        APP="\(appPath)"
        rm -rf "$APP"
        mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
        install -m 0755 "\(binary)" "$APP/Contents/MacOS/\(execName)"
        cat > "$APP/Contents/Info.plist" <<'PLIST'
        \(infoPlist)
        PLIST
        /usr/bin/codesign --force --sign - "$APP" 2>/dev/null || true
        """
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let osa = "do shell script \"\(escaped)\" with administrator privileges"

        do {
            let runner = ProcessRunner(containerPath: "/usr/bin/osascript")
            let result = try await runner.runExecutable(
                "/usr/bin/osascript",
                args: ["-e", osa],
                timeout: .seconds(120)
            )
            if result.succeeded {
                errorMessage = nil
            } else {
                errorMessage = result.stderr.isEmpty ? "Install failed (exit \(result.exitCode))" : result.stderr
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Volume / network actions

    func deleteVolume(_ name: String) async {
        let opID = beginOperation("deleteVolume", section: .volumes)
        defer { endOperation(opID) }
        do {
            try await service.deleteVolume(name: name)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteNetwork(_ id: String) async {
        let opID = beginOperation("deleteNetwork", section: .networks)
        defer { endOperation(opID) }
        do {
            try await service.deleteNetwork(id: id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
