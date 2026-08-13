//===----------------------------------------------------------------------===//
// MenuBarConfig — user-configurable metrics shown in the menu bar extra.
//
// Stored in UserDefaults as JSON (via RawRepresentable) so both the Settings
// view and the MenuBarView observe the same value through @AppStorage.
//
// The active items are kept as an ORDERED array (`activeItems`) so the user can
// both choose which metrics appear and control their display order. The old
// boolean schema is migrated automatically on first decode.
//
// NOTE: this type conforms to BOTH Codable and RawRepresentable (RawValue =
// String). Swift's synthesized Codable conformance for a RawRepresentable type
// encodes the `rawValue` property, which would call JSONEncoder().encode(self)
// again -> infinite recursion -> stack overflow. We therefore provide explicit
// init(from:)/encode(to:) that (de)serialize the actual stored fields.
//===----------------------------------------------------------------------===//

import Foundation
import CoreTransferable

/// A single selectable/orderable item in the menu bar extra.
enum MenuBarItem: String, CaseIterable, Identifiable, Codable, Transferable {
    case cpuRing, memoryRing
    case memoryUsed, memoryLimit
    case runningCount, containerCount, imageCount, volumeCount, networkCount, diskUsed
    case runtimeStatus
    case containerList, refresh, actions

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cpuRing: "CPU ring"
        case .memoryRing: "Memory ring"
        case .memoryUsed: "Memory used"
        case .memoryLimit: "Memory limit"
        case .runningCount: "Running containers"
        case .containerCount: "Total containers"
        case .imageCount: "Images"
        case .volumeCount: "Volumes"
        case .networkCount: "Networks"
        case .diskUsed: "Disk used"
        case .runtimeStatus: "Runtime status"
        case .containerList: "Container list"
        case .refresh: "Refresh action"
        case .actions: "Actions menu"
        }
    }

    var systemImage: String {
        switch self {
        case .cpuRing: "cpu"
        case .memoryRing: "memorychip"
        case .memoryUsed: "memorychip"
        case .memoryLimit: "memorychip"
        case .runningCount: "play.circle"
        case .containerCount: "shippingbox"
        case .imageCount: "photo.on.rectangle"
        case .volumeCount: "externaldrive"
        case .networkCount: "network"
        case .diskUsed: "internaldrive"
        case .runtimeStatus: "dot.radiowaves.left.and.right"
        case .containerList: "list.bullet"
        case .refresh: "arrow.clockwise"
        case .actions: "gearshape"
        }
    }

    /// Whether this item is a metric (rendered in the metrics section).
    var isMetric: Bool {
        switch self {
        case .cpuRing, .memoryRing, .memoryUsed, .memoryLimit,
             .runningCount, .containerCount, .imageCount, .volumeCount,
             .networkCount, .diskUsed, .runtimeStatus:
            return true
        default:
            return false
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .plainText)
    }
}

/// Which metrics and controls the menu bar extra should display, in order.
struct MenuBarConfig: Codable, Equatable, RawRepresentable {
    typealias RawValue = String

    /// The active items, in display order.
    var activeItems: [MenuBarItem] = [.cpuRing, .memoryRing, .runtimeStatus, .containerList, .refresh, .actions]
    var maxContainers = 8

    /// True when at least one metric or the runtime status is enabled.
    var hasMetrics: Bool {
        activeItems.contains { $0.isMetric }
    }

    var hasControls: Bool {
        activeItems.contains { $0 == .refresh || $0 == .actions }
    }

    var showContainerList: Bool {
        activeItems.contains(.containerList)
    }

    // MARK: - Init

    init() {}

    // MARK: - Codable (explicit, encodes fields not rawValue)

    private enum CodingKeys: String, CodingKey {
        case activeItems, maxContainers
    }

    /// Legacy boolean keys from the pre-ordering schema, used for migration.
    private enum LegacyKeys: String, CodingKey {
        case showCPU, showMemory, showMemoryUsed, showMemoryLimit
        case showRunningCount, showContainerCount, showImageCount
        case showVolumeCount, showNetworkCount, showDiskUsed
        case showRuntimeStatus, showContainerList, showRefresh, showActions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let items = try c.decodeIfPresent([MenuBarItem].self, forKey: .activeItems) {
            activeItems = items
        } else {
            // Migrate from the old boolean schema.
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            var items: [MenuBarItem] = []
            func add(_ item: MenuBarItem, _ key: LegacyKeys) {
                if (try? legacy.decodeIfPresent(Bool.self, forKey: key)) ?? false {
                    items.append(item)
                }
            }
            add(.cpuRing, .showCPU)
            add(.memoryRing, .showMemory)
            add(.memoryUsed, .showMemoryUsed)
            add(.memoryLimit, .showMemoryLimit)
            add(.runningCount, .showRunningCount)
            add(.containerCount, .showContainerCount)
            add(.imageCount, .showImageCount)
            add(.volumeCount, .showVolumeCount)
            add(.networkCount, .showNetworkCount)
            add(.diskUsed, .showDiskUsed)
            add(.runtimeStatus, .showRuntimeStatus)
            add(.containerList, .showContainerList)
            add(.refresh, .showRefresh)
            add(.actions, .showActions)
            if items.isEmpty {
                items = [.cpuRing, .memoryRing, .runtimeStatus, .containerList, .refresh, .actions]
            }
            activeItems = items
        }
        maxContainers = try c.decodeIfPresent(Int.self, forKey: .maxContainers) ?? 8
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(activeItems, forKey: .activeItems)
        try c.encode(maxContainers, forKey: .maxContainers)
    }

    // MARK: - RawRepresentable (JSON in UserDefaults)

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(MenuBarConfig.self, from: data) else {
            return nil
        }
        self = decoded
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
