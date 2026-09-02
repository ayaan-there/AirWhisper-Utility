import SwiftUI
import simd

/// SwiftUI port of the reference acceleration-channels line plot.
struct IMAAccelPlotView: View {

    let viz: IMAVisualizer
    @Binding var mode: String
    @Binding var frame: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Acceleration channels")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                legend
            }
            Canvas { context, size in
                drawPlot(context: context, size: size)
            }
            .frame(height: 180)
        }
    }

    private var accel: [SIMD3<Double>] { viz.accel(for: mode) }
    private var times: [Double] { viz.time }

    private var legend: some View {
        HStack(spacing: 10) {
            legendItem("X", color: axisColor("x"))
            legendItem("Y", color: axisColor("y"))
            legendItem("Z", color: axisColor("z"))
        }
    }

    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption2.weight(.semibold))
        }
    }

    private func drawPlot(context: GraphicsContext, size: CGSize) {
        guard !accel.isEmpty else { return }
        let pad = (left: 44.0, right: 16.0, top: 24.0, bottom: 24.0)
        let w = max(1, size.width - pad.left - pad.right)
        let h = max(1, size.height - pad.top - pad.bottom)

        let allAbs = accel.flatMap { [$0.x, $0.y, $0.z] }.map { abs($0) }
        let maxAbs = max(0.15, allAbs.max() ?? 0.15)
        let tMax = times.last ?? 1

        // horizontal gridlines
        for i in -2...2 {
            let y = pad.top + h / 2 - (Double(i) / 2) * h / 2
            var line = Path()
            line.move(to: CGPoint(x: pad.left, y: y))
            line.addLine(to: CGPoint(x: size.width - pad.right, y: y))
            context.stroke(line, with: .color(i == 0 ? .white.opacity(0.22) : .white.opacity(0.08)), lineWidth: 1)
        }

        func plot(_ axis: Int, color: Color) {
            var p = Path()
            for i in 0..<accel.count {
                let x = pad.left + (times[i] / tMax) * w
                let y = pad.top + h / 2 - (accel[i][axis] / maxAbs) * h * 0.46
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }

        plot(0, color: axisColor("x"))
        plot(1, color: axisColor("y"))
        plot(2, color: axisColor("z"))

        // time marker
        let markerX = pad.left + ((times[min(Int(frame), max(0, times.count - 1))] ) / tMax) * w
        var marker = Path()
        marker.move(to: CGPoint(x: markerX, y: pad.top))
        marker.addLine(to: CGPoint(x: markerX, y: pad.top + h))
        context.stroke(marker, with: .color(.white), lineWidth: 1)

        // labels
        context.draw(Text("g").font(.caption).foregroundColor(.secondary), at: CGPoint(x: 13, y: pad.top + 8))
        context.draw(Text(String(format: "%.1f s", tMax)).font(.caption).foregroundColor(.secondary), at: CGPoint(x: size.width - pad.right - 60, y: size.height - 8))
    }

    private func axisColor(_ axis: String) -> Color {
        switch axis {
        case "x": return Color(red: 1.0, green: 0.41, blue: 0.41)
        case "z": return Color(red: 0.46, green: 0.65, blue: 1.0)
        default: return Color(red: 0.19, green: 0.76, blue: 0.44)
        }
    }
}
