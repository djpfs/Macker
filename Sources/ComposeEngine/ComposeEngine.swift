//===----------------------------------------------------------------------===//
// ComposeEngine — custom Docker Compose implementation.
//
// This module parses docker-compose.yml files and orchestrates the containers,
// networks and volumes of a project on top of ContainerBackend. Components:
//   • ComposeParser / ComposeModels        — YAML + interpolation + validation
//   • ServiceResolver                     — topological sort on depends_on
//   • ComposeOrchestrator                 — up/down/ps/logs in dependency order
//   • HealthChecker (in orchestrator)      — polling health checks
//   • HostsFileSync (in orchestrator)     — /etc/hosts entries for service DNS
//===----------------------------------------------------------------------===//

import Foundation

/// Namespace for the Compose engine. All public API hangs off this type.
public enum ComposeEngine {
    /// Version of the Compose spec this engine targets.
    public static let supportedSpecVersion = "3.8"
}
