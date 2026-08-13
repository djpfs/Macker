//===----------------------------------------------------------------------===//
// DashboardChartsView — general statistics charts (CPU, Memory, I/O) with the
// ability to filter by a single container or aggregate across all running
// containers. Series are derived from AppState.statsHistory.
//===----------------------------------------------------------------------===//

import SwiftUI
import ContainerBackend

/// A named time series for a chart.
private struct Series {
    let name: String
    let color: Color
    let values: [Double]
}

/// The time window shown on the dashboard charts.
private enum ChartInterval: String, CaseIterable, Identifiable {
    case oneMinute = "1m"
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"
    case oneHour = "1h"

    var id: String { rawValue }

    /// The window length in seconds.
    var seconds: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        case .thirtyMinutes: 1800
        case .oneHour: 3600
        }
    }
}

/// The dashboard statistics section: a container filter plus CPU/Memory/I/O
/// charts.
struct DashboardChartsView: View {
    @Environment(AppState.self) private var state
    @State private var selectedContainer: String?
    @State private var interval: ChartInterval = .fiveMinutes

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Statistics")
                    .font(.headline)
                Spacer()
                Picker("Interval", selection: $interval) {
                    ForEach(ChartInterval.allCases) { interval in
                        Text(interval.rawValue).tag(interval)
                    }
                }
                .labelsHidden()
                .frame(width: 80)
                Picker("Container", selection: $selectedContainer) {
                    Text("All containers").tag(String?.none)
                    ForEach(runningContainers) { container in
                        Text(container.id).tag(String?.some(container.id))
                    }
                }
                .labelsHidden()
                .frame(width: 240)
            }

            if state.statsHistory.isEmpty {
                Text("Collecting statistics...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                MetricChart(title: "CPU", unit: "%", series: cpuSeries)
                MetricChart(title: "Memory", unit: "bytes", series: memorySeries)
                MetricChart(title: "Block I/O", unit: "bytes/s", series: ioSeries)
            }
        }
    }

    private var runningContainers: [ContainerSnapshot] {
        state.containers.filter { $0.status == .running }
    }

    /// Whether the filter targets a single container or all running ones.
    private var isFiltered: Bool { selectedContainer != nil }

    // MARK: - Series computation

    private var cpuSeries: [Series] {
        [Series(name: "CPU", color: .blue, values: cpuPercentSeries)]
    }

    private var memorySeries: [Series] {
        [Series(name: "Memory", color: .orange, values: memoryBytesSeries)]
    }

    private var ioSeries: [Series] {
        [
            Series(name: "Read", color: .green, values: ioReadSeries),
            Series(name: "Write", color: .red, values: ioWriteSeries),
        ]
    }

    /// CPU usage percent per sample (rate between consecutive samples).
    private var cpuPercentSeries: [Double] {
        let samples = windowedSamples
        guard samples.count >= 2 else { return [] }
        var result: [Double] = []
        for i in 1..<samples.count {
            let prev = samples[i - 1]
            let curr = samples[i]
            let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
            guard dt > 0 else { continue }
            let prevUsec = cpuUsec(in: prev)
            let currUsec = cpuUsec(in: curr)
            // Guard against counter resets / container removal between samples.
            let deltaUsec = currUsec > prevUsec ? currUsec - prevUsec : 0
            let deltaSeconds = Double(deltaUsec) / 1_000_000
            result.append(deltaSeconds / dt * 100)
        }
        return result
    }

    /// Memory usage in bytes per sample.
    private var memoryBytesSeries: [Double] {
        windowedSamples.map { Double(memoryBytes(in: $0)) }
    }

    /// Block read rate (bytes/s) per sample.
    private var ioReadSeries: [Double] {
        rateSeries { $0.blockReadBytes ?? 0 }
    }

    /// Block write rate (bytes/s) per sample.
    private var ioWriteSeries: [Double] {
        rateSeries { $0.blockWriteBytes ?? 0 }
    }

    /// Compute a per-second rate for a cumulative counter across samples.
    private func rateSeries(_ counter: @escaping (ContainerStats) -> UInt64) -> [Double] {
        let samples = windowedSamples
        guard samples.count >= 2 else { return [] }
        var result: [Double] = []
        for i in 1..<samples.count {
            let prev = samples[i - 1]
            let curr = samples[i]
            let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
            guard dt > 0 else { continue }
            let prevValue = aggregate(in: prev, counter: counter)
            let currValue = aggregate(in: curr, counter: counter)
            // Guard against counter resets / container removal between samples.
            let delta = currValue > prevValue ? currValue - prevValue : 0
            result.append(Double(delta) / dt)
        }
        return result
    }

    /// Sum a counter across the selected containers in a sample.
    private func aggregate(in sample: StatsSample, counter: (ContainerStats) -> UInt64) -> UInt64 {
        selectedStats(in: sample).reduce(0) { $0 + counter($1) }
    }

    /// Sum CPU microseconds across the selected containers in a sample.
    private func cpuUsec(in sample: StatsSample) -> UInt64 {
        selectedStats(in: sample).reduce(0) { $0 + ($1.cpuUsageUsec ?? 0) }
    }

    /// Sum memory bytes across the selected containers in a sample.
    private func memoryBytes(in sample: StatsSample) -> UInt64 {
        selectedStats(in: sample).reduce(0) { $0 + ($1.memoryUsageBytes ?? 0) }
    }

    /// The stats samples within the selected time window, oldest first.
    private var windowedSamples: [StatsSample] {
        let cutoff = Date().addingTimeInterval(-interval.seconds)
        return state.statsHistory.filter { $0.timestamp >= cutoff }
    }

    /// The stats for the selected container, or all containers in the sample.
    private func selectedStats(in sample: StatsSample) -> [ContainerStats] {
        if let id = selectedContainer {
            return sample.stats[id].map { [$0] } ?? []
        }
        return Array(sample.stats.values)
    }
}

/// A titled chart with one or more overlaid series.
private struct MetricChart: View {
    let title: String
    let unit: String
    let series: [Series]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                HStack(spacing: 12) {
                    ForEach(series, id: \.name) { s in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(s.color)
                                .frame(width: 8, height: 8)
                            Text(s.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            ZStack {
                Sparkline(values: series.first?.values ?? [], color: series.first?.color ?? .accentColor)
                ForEach(series.dropFirst(), id: \.name) { s in
                    Sparkline(values: s.values, color: s.color)
                }
            }
            .frame(height: 90)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
            )

            if let last = series.first?.values.last {
                Text("\(title): \(format(last)) \(unit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func format(_ value: Double) -> String {
        if unit == "%" {
            return String(format: "%.1f", value)
        }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }
}
