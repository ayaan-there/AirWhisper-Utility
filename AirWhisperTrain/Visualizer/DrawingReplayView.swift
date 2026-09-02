import SwiftUI
import Combine

/// Replays a captured `DrawingPattern` (how a letter was drawn on the phone
/// canvas) with play/pause and a scrubber, showing the pen pattern in motion.
struct DrawingReplayView: View {

    let pattern: DrawingPattern
    var showControls = true

    @State private var t: TimeInterval = 0
    @State private var isPlaying = false
    @State private var visitedOnce = false
    private let timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            drawingCanvas
            if showControls {
                controls
            }
        }
        .onAppear {
            if !visitedOnce {
                visitedOnce = true
                isPlaying = true
            }
        }
        .onReceive(timer) { _ in
            guard isPlaying, pattern.duration > 0 else { return }
            t += 1.0 / 30.0
            if t >= pattern.duration {
                t = 0
            }
        }
        .onDisappear {
            isPlaying = false
        }
    }

    private var drawingCanvas: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let scale = min(w, h)

            for stroke in pattern.strokes where stroke.points.count >= 2 && !stroke.isEraser {
                let start = stroke.startTime
                let end = start + (stroke.points.last?.time ?? 0)
                guard t >= start else { continue }

                var visible: [CGPoint] = []
                for i in 0..<stroke.points.count {
                    let p = stroke.points[i]
                    let global = start + p.time
                    if global <= t {
                        visible.append(normToView(p, w: w, h: h, scale: scale))
                    } else if i > 0 {
                        let prev = stroke.points[i - 1]
                        let prevGlobal = start + prev.time
                        let span = p.time - prev.time
                        let ratio = span <= 0 ? 0 : (t - prevGlobal) / span
                        let x = prev.x + (p.x - prev.x) * ratio
                        let y = prev.y + (p.y - prev.y) * ratio
                        visible.append(normToView(DrawingPattern.Point(x: x, y: y, time: prev.time + span * ratio), w: w, h: h, scale: scale))
                        break
                    }
                }

                if visible.count >= 2 {
                    var path = Path()
                    path.move(to: visible[0])
                    for pt in visible.dropFirst() {
                        path.addLine(to: pt)
                    }
                    let width = CGFloat(stroke.width) * (scale / max(w, h))
                    context.stroke(path, with: .color(AppTheme.brandBlue), style: StrokeStyle(lineWidth: max(2, width), lineCap: .round, lineJoin: .round))
                }
            }

            if activePen, t < pattern.duration {
                let pos = normToView(activePenCoord, w: w, h: h, scale: scale)
                context.fill(Path(ellipseIn: CGRect(x: pos.x - 4, y: pos.y - 4, width: 8, height: 8)), with: .color(AppTheme.brandBlue))
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1.0, contentMode: .fit)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                playPause()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(AppTheme.brandBlue)
            }
            .buttonStyle(.plain)

            Button {
                restart()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 18))
                    .foregroundStyle(AppTheme.brandBlue)
            }
            .buttonStyle(.plain)

            Slider(value: $t, in: 0...max(pattern.duration, 0.01)) { editing in
                if editing {
                    isPlaying = false
                }
            }
            .tint(AppTheme.brandBlue)

            Text(String(format: "%.1fs", pattern.duration))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .trailing)
        }
    }

    private func normToView(_ p: DrawingPattern.Point, w: CGFloat, h: CGFloat, scale: CGFloat) -> CGPoint {
        let x = (CGFloat(p.x) * w - w / 2) * scale / max(w, h) + w / 2
        let y = (CGFloat(p.y) * h - h / 2) * scale / max(w, h) + h / 2
        return CGPoint(x: x, y: y)
    }

    private var activePenCoord: DrawingPattern.Point {
        let pt = pattern.point(at: t)
        if let pt {
            return DrawingPattern.Point(x: Double(pt.x), y: Double(pt.y), time: 0)
        }
        return .init(x: 0.5, y: 0.5, time: 0)
    }

    private var activePen: Bool {
        pattern.point(at: t) != nil
    }

    private func playPause() {
        if isPlaying {
            isPlaying = false
        } else {
            if t >= pattern.duration { t = 0 }
            isPlaying = true
        }
    }

    private func restart() {
        t = 0
        isPlaying = true
    }
}
