//===----------------------------------------------------------------------===//
// ContainerSettingsView — edit a container's configuration (networks, ports,
// resources, environment, labels) and apply by recreating the container.
//
// The apple/container runtime does not support mutating a running container
// (e.g. attaching a network or changing a published port on the fly), so
// changes are applied by recreating the container with the new config.
//===----------------------------------------------------------------------===//

import SwiftUI
import ContainerBackend

/// Editable fields for a container, initialized from its configuration.
private struct SettingsModel {
    var networks: [String]
    var ports: [PortEntry]
    var memoryMB: String
    var cpus: String
    var envVars: [String]
    var labels: [String: String]

    struct PortEntry: Identifiable {
        let id = UUID()
        var hostPort: String
        var containerPort: String
        var proto: PublishProtocol
    }

    init(container: ContainerSnapshot) {
        let config = container.configuration
        networks = config.networks.map(\.network)
        ports = config.publishedPorts.map {
            PortEntry(hostPort: String($0.hostPort),
                      containerPort: String($0.containerPort),
                      proto: $0.proto)
        }
        if let mem = config.resources.memoryInBytes {
            memoryMB = String(mem / (1024 * 1024))
        } else {
            memoryMB = ""
        }
        if let cpuCount = config.resources.cpus {
            cpus = String(cpuCount)
        } else {
            cpus = ""
        }
        envVars = config.initProcess.environment
        labels = config.labels
    }
}

/// The Settings tab for a selected container.
struct ContainerSettingsView: View {
    @Environment(AppState.self) private var state
    let container: ContainerSnapshot
    @State private var model: SettingsModel
    @State private var newEnvVar = ""
    @State private var newLabelKey = ""
    @State private var newLabelValue = ""
    @State private var applyError: String?
    @State private var isApplying = false

    init(container: ContainerSnapshot) {
        self.container = container
        _model = State(initialValue: SettingsModel(container: container))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                networksSection
                portsSection
                resourcesSection
                envSection
                labelsSection

                Divider()

                HStack {
                    Button("Apply changes") {
                        apply()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isApplying)

                    if isApplying {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let applyError {
                        Text(applyError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        // When the container is recreated (e.g. after Apply), its creation
        // date changes. Re-initialize the model from the fresh snapshot so the
        // applied changes (env vars, ports, etc.) show up. During normal
        // polling the creation date is stable, so in-progress edits are kept.
        .onChange(of: container.configuration.creationDate) {
            model = SettingsModel(container: container)
            applyError = nil
        }
    }

    // MARK: - Networks

    private var networksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Networks")
                .font(.headline)
            Text("Select the networks this container is attached to. Changes are applied by recreating the container.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(state.networks) { network in
                Toggle(network.name, isOn: binding(for: network.name))
            }
            if state.networks.isEmpty {
                Text("No networks available")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func binding(for network: String) -> Binding<Bool> {
        Binding(
            get: { model.networks.contains(network) },
            set: { isOn in
                if isOn {
                    if !model.networks.contains(network) {
                        model.networks.append(network)
                    }
                } else {
                    model.networks.removeAll { $0 == network }
                }
            }
        )
    }

    // MARK: - Ports

    private var portsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Published ports")
                .font(.headline)

            ForEach($model.ports) { $port in
                HStack(spacing: 8) {
                    TextField("Host", text: $port.hostPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text(":")
                    TextField("Container", text: $port.containerPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Picker("", selection: $port.proto) {
                        Text("tcp").tag(PublishProtocol.tcp)
                        Text("udp").tag(PublishProtocol.udp)
                    }
                    .labelsHidden()
                    .frame(width: 80)
                    Button {
                        model.ports.removeAll { $0.id == port.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Button {
                model.ports.append(SettingsModel.PortEntry(hostPort: "", containerPort: "", proto: .tcp))
            } label: {
                Label("Add port", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Resources

    private var resourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resources")
                .font(.headline)

            HStack {
                Text("Memory limit (MB)")
                    .frame(width: 150, alignment: .leading)
                TextField("empty = default", text: $model.memoryMB)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }

            HStack {
                Text("CPU count")
                    .frame(width: 150, alignment: .leading)
                TextField("empty = default", text: $model.cpus)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Environment

    private var envSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Environment")
                .font(.headline)

            ForEach(Array(model.envVars.enumerated()), id: \.offset) { index, entry in
                HStack(spacing: 8) {
                    TextField("KEY=VALUE", text: Binding(
                        get: { model.envVars[index] },
                        set: { model.envVars[index] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Button {
                        model.envVars.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack(spacing: 8) {
                TextField("KEY=VALUE", text: $newEnvVar)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let trimmed = newEnvVar.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        model.envVars.append(trimmed)
                        newEnvVar = ""
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Labels

    private var labelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Labels")
                .font(.headline)

            ForEach(model.labels.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack(spacing: 8) {
                    Text(key)
                        .frame(width: 180, alignment: .leading)
                    Text(value)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.labels.removeValue(forKey: key)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack(spacing: 8) {
                TextField("Key", text: $newLabelKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                TextField("Value", text: $newLabelValue)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let key = newLabelKey.trimmingCharacters(in: .whitespaces)
                    if !key.isEmpty {
                        model.labels[key] = newLabelValue
                        newLabelKey = ""
                        newLabelValue = ""
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Apply

    private func apply() {
        applyError = nil
        isApplying = true
        Task { @MainActor in
            defer { isApplying = false }
            do {
                let config = try buildConfiguration()
                await state.applyContainerConfig(container.id, configuration: config)
            } catch {
                applyError = error.localizedDescription
            }
        }
    }

    private func buildConfiguration() throws -> ContainerConfiguration {
        var config = container.configuration

        // Networks
        config.networks = model.networks.map { AttachmentConfiguration(network: $0) }

        // Ports
        var ports: [PublishPort] = []
        for entry in model.ports {
            let host = entry.hostPort.trimmingCharacters(in: .whitespaces)
            let containerPort = entry.containerPort.trimmingCharacters(in: .whitespaces)
            guard !host.isEmpty, !containerPort.isEmpty,
                  let hostValue = UInt16(host),
                  let containerValue = UInt16(containerPort) else {
                throw SettingsError.invalidPort(entry.hostPort, entry.containerPort)
            }
            ports.append(PublishPort(hostAddress: IPAddress("0.0.0.0"),
                                     hostPort: hostValue,
                                     containerPort: containerValue,
                                     proto: entry.proto,
                                     count: 1))
        }
        config.publishedPorts = ports

        // Resources
        let memText = model.memoryMB.trimmingCharacters(in: .whitespaces)
        if memText.isEmpty {
            config.resources.memoryInBytes = nil
        } else {
            guard let mb = UInt64(memText) else {
                throw SettingsError.invalidNumber("Memory limit", memText)
            }
            config.resources.memoryInBytes = mb * 1024 * 1024
        }

        let cpuText = model.cpus.trimmingCharacters(in: .whitespaces)
        if cpuText.isEmpty {
            config.resources.cpus = nil
        } else {
            guard let cpus = Int(cpuText), cpus > 0 else {
                throw SettingsError.invalidNumber("CPU count", cpuText)
            }
            config.resources.cpus = cpus
        }

        // Environment
        config.initProcess.environment = model.envVars

        // Labels
        config.labels = model.labels

        return config
    }
}

/// Errors surfaced when building a modified container configuration.
private enum SettingsError: LocalizedError {
    case invalidPort(String, String)
    case invalidNumber(String, String)

    var errorDescription: String? {
        switch self {
        case .invalidPort(let host, let container):
            return "Invalid port mapping: host=\(host), container=\(container)"
        case .invalidNumber(let field, let value):
            return "Invalid \(field): \(value)"
        }
    }
}
