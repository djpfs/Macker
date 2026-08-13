//===----------------------------------------------------------------------===//
// StatusBadge — a colored pill showing a container's runtime status.
//===----------------------------------------------------------------------===//

import SwiftUI
import ContainerBackend

/// A colored pill for a container status.
struct StatusBadge: View {
    let status: RuntimeStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .running: .green
        case .stopped: .gray
        case .stopping: .orange
        case .unknown: .secondary
        }
    }
}

/// A colored dot for a container status (used in compact rows).
struct StatusDot: View {
    let status: RuntimeStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch status {
        case .running: .green
        case .stopped: .gray
        case .stopping: .orange
        case .unknown: .secondary
        }
    }
}
