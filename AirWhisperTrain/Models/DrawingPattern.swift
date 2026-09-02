import Foundation

/// A timed, replayable capture of how a letter was drawn on the phone canvas.
/// Points are normalized to 0-1 relative to the canvas so they can be replayed
/// at any view size. `time`/`startTime` are seconds on a global timeline from
/// the start of the drawing, which lets the pattern be replayed stroke-by-stroke.
struct DrawingPattern: Codable, Equatable, Hashable {

    struct Point: Codable, Equatable, Hashable {
        var x: Double
        var y: Double
        var time: TimeInterval
    }

    struct Stroke: Codable, Equatable, Hashable {
        var points: [Point]
        var width: Double
        var isEraser: Bool
        var startTime: TimeInterval
    }

    var strokes: [Stroke]
    var duration: TimeInterval

    var isEmpty: Bool { strokes.isEmpty }

    /// A point offset by `t` seconds; returns the interpolated pen position
    /// within the stroke that is being traced at global time `t`, or nil when
    /// the stroke hasn't started at that time.
    func point(at t: TimeInterval) -> CGPoint? {
        guard !strokes.isEmpty else { return nil }
        var lastPoint: CGPoint?
        for stroke in strokes {
            guard stroke.points.count >= 2, stroke.isEraser == false else { continue }
            let start = stroke.startTime
            let end = start + (stroke.points.last?.time ?? 0)
            guard t >= start, t <= end else { continue }
            let local = t - start
            var prev = stroke.points[0]
            for p in stroke.points.dropFirst() {
                if local <= p.time {
                    let span = p.time - prev.time
                    let ratio = span <= 0 ? 0 : (local - prev.time) / span
                    lastPoint = CGPoint(
                        x: prev.x + (p.x - prev.x) * ratio,
                        y: prev.y + (p.y - prev.y) * ratio
                    )
                    return lastPoint
                }
                prev = p
            }
        }
        return lastPoint
    }

    /// Returns the number of pen-down segments fully drawn by global time `t`.
    func progress(at t: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, t / duration))
    }
}
