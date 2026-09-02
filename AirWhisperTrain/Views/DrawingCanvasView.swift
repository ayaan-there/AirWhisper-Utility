import UIKit
import SwiftUI
import Combine

struct StrokePoint: Equatable {
    var point: CGPoint
    var time: TimeInterval
}

struct Stroke: Equatable {
    var points: [StrokePoint]
    var color: UIColor
    var width: CGFloat
    var isEraser: Bool
    var startTime: TimeInterval
}

@MainActor
/// Manages the drawing state for letter template capture.
///
/// Handles stroke collection, undo/redo, and conversion to `DrawingPattern`
/// for synchronized playback with IMU recordings.
/// 
/// Thread Safety: All published properties and methods are @MainActor.
final class DrawingSession: ObservableObject {
    @Published var color: Color = .black
    @Published var width: CGFloat = 6
    @Published var isEraser: Bool = false
    @Published private(set) var strokeCount: Int = 0
    @Published private(set) var redoCount: Int = 0
    @Published private(set) var duration: TimeInterval = 0

    fileprivate var strokes: [Stroke] = []
    fileprivate var redoStack: [Stroke] = []
    private var patternStart: Date?
    fileprivate var canvasSize: CGSize = .zero
    private let patternLock = NSLock()

    var hasStrokes: Bool { !strokes.isEmpty }

    fileprivate func add(_ stroke: Stroke) {
        strokes.append(stroke)
        redoStack.removeAll()
        strokeCount = strokes.count
        redoCount = 0
        duration = strokes.map { $0.startTime + ($0.points.last?.time ?? 0) }.max() ?? 0
    }

    func undo() {
        guard let last = strokes.popLast() else { return }
        redoStack.append(last)
        strokeCount = strokes.count
        redoCount = redoStack.count
        duration = strokes.map { $0.startTime + ($0.points.last?.time ?? 0) }.max() ?? 0
    }

    func redo() {
        guard let last = redoStack.popLast() else { return }
        strokes.append(last)
        strokeCount = strokes.count
        redoCount = redoStack.count
        duration = strokes.map { $0.startTime + ($0.points.last?.time ?? 0) }.max() ?? 0
    }

    func clear() {
        strokes.removeAll()
        redoStack.removeAll()
        patternStart = nil
        strokeCount = 0
        redoCount = 0
        duration = 0
    }

    fileprivate func beginCapture(size: CGSize) {
        patternLock.lock()
        defer { patternLock.unlock() }
        canvasSize = size
        if patternStart == nil {
            patternStart = Date()
        }
    }

    fileprivate func currentTime() -> TimeInterval {
        patternStart.map { Date().timeIntervalSince($0) } ?? 0
    }

    func makePattern() -> DrawingPattern? {
        guard !strokes.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let w = canvasSize.width
        let h = canvasSize.height
        let outStrokes = strokes.map { s -> DrawingPattern.Stroke in
            let pts = s.points.map { sp -> DrawingPattern.Point in
                DrawingPattern.Point(x: Double(sp.point.x / w), y: Double(sp.point.y / h), time: sp.time)
            }
            return DrawingPattern.Stroke(points: pts, width: Double(s.width), isEraser: s.isEraser, startTime: s.startTime)
        }
        return DrawingPattern(strokes: outStrokes, duration: duration)
    }
}

final class DrawingCanvasView: UIView {

    weak var session: DrawingSession? {
        didSet { setNeedsDisplay() }
    }

    // Reuse buffer to avoid allocation on every touch move
    private var currentPoints: [StrokePoint] = []
    private var currentPointsCapacity: Int = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let session else { return }
        session.beginCapture(size: bounds.size)
        let time = session.currentTime()
        // Pre-allocate buffer
        currentPoints = [StrokePoint(point: touch.location(in: self), time: time)]
        currentPointsCapacity = 1
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let session else { return }
        // Append to pre-allocated buffer
        if currentPoints.count >= currentPointsCapacity {
            currentPoints.append(StrokePoint(point: touch.location(in: self), time: session.currentTime()))
            currentPointsCapacity = currentPoints.count
        } else {
            currentPoints[currentPoints.count] = StrokePoint(point: touch.location(in: self), time: session.currentTime())
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let session else { return }
        if currentPoints.count < currentPointsCapacity {
            currentPoints[currentPoints.count] = StrokePoint(point: touch.location(in: self), time: session.currentTime())
        } else {
            currentPoints.append(StrokePoint(point: touch.location(in: self), time: session.currentTime()))
        }
        currentPointsCapacity = currentPoints.count
        
        let stroke = Stroke(points: currentPoints, color: session.isEraser ? .white : UIColor(session.color), width: session.width, isEraser: session.isEraser, startTime: session.currentTime())
        session.add(stroke)
        currentPoints.removeAll(keepingCapacity: true)
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentPoints.removeAll(keepingCapacity: true)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        if let session {
            for stroke in session.strokes {
                drawStroke(stroke, in: ctx)
            }
            if currentPoints.count >= 2, session.isEraser {
                let live = Stroke(points: currentPoints, color: .white, width: session.width, isEraser: true, startTime: 0)
                drawStroke(live, in: ctx)
            }
        }
    }

    private func drawStroke(_ stroke: Stroke, in ctx: CGContext) {
        guard stroke.points.count >= 2 else { return }
        ctx.saveGState()
        if stroke.isEraser {
            ctx.setBlendMode(.clear)
        }
        ctx.setStrokeColor(stroke.color.cgColor)
        ctx.setLineWidth(stroke.width)
        ctx.beginPath()
        var prev = stroke.points[0].point
        ctx.move(to: prev)
        for sp in stroke.points.dropFirst() {
            let p = sp.point
            let mid = CGPoint(x: (prev.x + p.x) / 2, y: (prev.y + p.y) / 2)
            ctx.addQuadCurve(to: mid, control: prev)
            prev = p
        }
        ctx.addLine(to: stroke.points.last!.point)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

struct DrawCanvasRepresentable: UIViewRepresentable {
    let session: DrawingSession

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> DrawingCanvasView {
        let view = DrawingCanvasView()
        view.session = session
        // Don't retain session in coordinator - use weak reference
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: DrawingCanvasView, context: Context) {
        uiView.session = session
        // Only trigger redraw when strokeCount changes (not on every point)
        if context.coordinator.lastStrokeCount != session.strokeCount {
            context.coordinator.lastStrokeCount = session.strokeCount
            uiView.setNeedsDisplay()
        }
    }

    final class Coordinator {
        weak var view: DrawingCanvasView?
        var lastStrokeCount: Int = -1
    }
}
