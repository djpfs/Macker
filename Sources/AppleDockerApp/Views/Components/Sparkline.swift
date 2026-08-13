//===----------------------------------------------------------------------===//
// Sparkline — a tiny inline chart for a series of values.
//===----------------------------------------------------------------------===//

import SwiftUI

/// A minimal line chart for a time series of values.
struct Sparkline: View {
    /// The values to plot, oldest first.
    let values: [Double]
    /// The color of the line.
    var color: Color = .accentColor
    /// The line width.
    var lineWidth: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            let points = normalizedPoints(in: geo.size)
            ZStack {
                // Fill under the line.
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geo.size.height))
                    for point in points {
                        path.addLine(to: point)
                    }
                    path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(color.opacity(0.12))

                // The line itself.
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// Map the values into view coordinates.
    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty, size.width > 0, size.height > 0 else { return [] }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let range = max(maxValue - minValue, 0.0001)
        let step = size.width / CGFloat(max(values.count - 1, 1))
        return values.enumerated().map { index, value in
            let x = CGFloat(index) * step
            let y = size.height - CGFloat((value - minValue) / range) * size.height
            return CGPoint(x: x, y: y)
        }
    }
}
