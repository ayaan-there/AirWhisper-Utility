import SwiftUI
import simd
import Combine

/// SwiftUI port of the reference 3D scene: perspective-projected 3D trajectory
/// with a quaternion-oriented watch cube, axis grid, and timeline scrubber.
struct IMASceneView: View {

    let viz: IMAVisualizer
    @Binding var mode: String
    @Binding var frame: Double

    @State private var yaw: Double = -0.78
    @State private var pitch: Double = 0.55
    @State private var roll: Double = 0
    @State private var zoom: Double = 1.0
    @State private var playing = false

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            modePicker
            Canvas { context, size in
                drawScene(context: context, size: size)
            }
            .gesture(orbitGesture)
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            scrubBar
            playButton
        }
        .onReceive(timer) { _ in
            guard playing else { return }
            let n = viz.path(for: mode).count
            let fps = n > 0 && viz.duration > 0 ? Double(n) / viz.duration : 30
            frame += 0.05 * fps
            if frame >= Double(max(0, n - 1)) { frame = 0 }
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(IMAVisualizer.modeNames, id: \.self) { m in
                Text(IMAVisualizer.modeLabel(m)).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var scrubBar: some View {
        VStack(spacing: 4) {
            Slider(value: $frame, in: 0...Double(max(0, viz.path(for: mode).count - 1)), step: 1)
            HStack {
                Text("t = \(frameTime, specifier: "%.2f") s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Mode: \(IMAVisualizer.modeLabel(mode))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var frameTime: Double {
        let idx = Int(frame)
        let t = viz.time
        if idx >= 0 && idx < t.count { return t[idx] }
        return viz.duration * (Double(idx) / Double(max(1, t.count - 1)))
    }

    private var playButton: some View {
        Button {
            playing.toggle()
        } label: {
            Label(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.brandBlue)
    }

    private var orbitGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation.width != 0 {
                    yaw += Double(value.translation.width) * 0.008
                }
                pitch = simd_clamp(pitch + Double(value.translation.height) * 0.008, -Double.pi, Double.pi)
            }
            .simultaneously(with: MagnifyGesture().onChanged { value in
                zoom = simd_clamp(zoom * Double(value.magnification), 0.35, 3.5)
            })
    }

    // MARK: - Scene drawing

    private struct Projector {
        let width: CGFloat
        let height: CGFloat
        let center: SIMD3<Double>
        let range: Double
        let yaw: Double
        let pitch: Double
        let roll: Double
        let zoom: Double

        func project(_ point: SIMD3<Double>) -> (x: CGFloat, y: CGFloat, depth: Double) {
            let p = point - center
            let cy = cos(yaw), sy = sin(yaw)
            let cp = cos(pitch), sp = sin(pitch)
            let cr = cos(roll), sr = sin(roll)
            let x1 = cy * p.x - sy * p.y
            let y1 = sy * p.x + cy * p.y
            let z1 = p.z
            let y2 = cp * y1 - sp * z1
            let z2 = sp * y1 + cp * z1
            let x3 = cr * x1 - sr * y2
            let y3 = sr * x1 + cr * y2
            let drawScale = min(width, height) * 0.62 / max(range, 0.001) * zoom
            let distance = 3.2
            let depth = max(0.35, distance - z2)
            let perspective = distance / depth
            return (width / 2 + CGFloat(x3 * drawScale * perspective),
                    height / 2 - CGFloat(y3 * drawScale * perspective),
                    depth)
        }
    }

    private func drawScene(context: GraphicsContext, size: CGSize) {
        let path = viz.path(for: mode)
        guard !path.isEmpty else { return }
        let box = bounds(of: [path])
        let projector = Projector(width: min(size.width, 1000), height: size.height, center: box.center, range: box.range, yaw: yaw, pitch: pitch, roll: roll, zoom: zoom)

        // background
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.05, green: 0.07, blue: 0.09)))

        drawGrid(context: context, size: size, projector: projector, range: box.range)

        // trajectory underlay
        drawPath(context: context, projector: projector, path: path, color: .white.opacity(0.18), width: 2, limit: path.count)

        // colored path up to current frame
        let limit = Int(frame) + 1
        let color = axisColor("y")
        drawPath(context: context, projector: projector, path: path, color: color, width: 4, limit: limit, alpha: 0.95)

        let position = path[Int(clampFrame(frame))]

        // start + current points
        if let first = path.first {
            drawPoint(context: context, projector: projector, point: first, color: .white, radius: 4)
        }
        drawPoint(context: context, projector: projector, point: position, color: axisColor("y"), radius: 6)

        // watch cube oriented by quaternion
        let qList = viz.quaternions(for: mode)
        let quat = qList.isEmpty ? SIMD4(1, 0, 0, 0) : qList[Int(clampFrame(frame))]
        drawCube(context: context, projector: projector, position: position, quat: quat, size: max(0.025, box.range * 0.055))
    }

    private func clampFrame(_ value: Double) -> Double {
        let n = viz.path(for: mode).count
        return min(max(0, value), Double(max(0, n - 1)))
    }

    private func drawGrid(context: GraphicsContext, size: CGSize, projector: Projector, range: Double) {
        let step = niceStep(range)
        let limit = step * ceil(range / step)
        var x = -limit
        while x <= limit + step * 0.5 {
            line(context, projector, SIMD3(x, -limit, 0), SIMD3(x, limit, 0), .white.opacity(0.06), 1)
            x += step
        }
        var y = -limit
        while y <= limit + step * 0.5 {
            line(context, projector, SIMD3(-limit, y, 0), SIMD3(limit, y, 0), .white.opacity(0.06), 1)
            y += step
        }
        line(context, projector, SIMD3(-limit, 0, 0), SIMD3(limit, 0, 0), Color(red: 0.81, green: 0.22, blue: 0.22).opacity(0.55), 1.4)
        line(context, projector, SIMD3(0, -limit, 0), SIMD3(0, limit, 0), Color(red: 0.12, green: 0.61, blue: 0.33).opacity(0.55), 1.4)
        line(context, projector, SIMD3(0, 0, -limit * 0.35), SIMD3(0, 0, limit), Color(red: 0.18, green: 0.39, blue: 0.84).opacity(0.55), 1.4)

        axisText(context, projector, SIMD3(limit, 0, 0), "+X", axisColor("x"))
        axisText(context, projector, SIMD3(-limit, 0, 0), "-X", axisColor("x"))
        axisText(context, projector, SIMD3(0, limit, 0), "+Y", axisColor("y"))
        axisText(context, projector, SIMD3(0, -limit, 0), "-Y", axisColor("y"))
        axisText(context, projector, SIMD3(0, 0, limit), "+Z", axisColor("z"))
        axisText(context, projector, SIMD3(0, 0, -limit * 0.35), "-Z", axisColor("z"))
    }

    private func drawPath(context: GraphicsContext, projector: Projector, path: [SIMD3<Double>], color: Color, width: CGFloat, limit: Int, alpha: Double = 1.0) {
        let n = min(limit, path.count)
        guard n >= 2 else { return }
        var p = Path()
        for i in 0..<n {
            let pt = projector.project(path[i])
            if i == 0 { p.move(to: CGPoint(x: pt.x, y: pt.y)) }
            else { p.addLine(to: CGPoint(x: pt.x, y: pt.y)) }
        }
        context.stroke(p, with: .color(color.opacity(alpha)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func drawPoint(context: GraphicsContext, projector: Projector, point: SIMD3<Double>, color: Color, radius: CGFloat) {
        let pt = projector.project(point)
        context.fill(Path(ellipseIn: CGRect(x: pt.x - radius, y: pt.y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
    }

    private func line(_ context: GraphicsContext, _ projector: Projector, _ a: SIMD3<Double>, _ b: SIMD3<Double>, _ color: Color, _ width: CGFloat) {
        let pa = projector.project(a)
        let pb = projector.project(b)
        var p = Path()
        p.move(to: CGPoint(x: pa.x, y: pa.y))
        p.addLine(to: CGPoint(x: pb.x, y: pb.y))
        context.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width))
    }

    private func axisText(_ context: GraphicsContext, _ projector: Projector, _ point: SIMD3<Double>, _ text: String, _ color: Color) {
        let pt = projector.project(point)
        var resolved = context.resolve(Text(text).font(.system(size: 12, weight: .bold)))
        resolved.shading = .color(color)
        context.draw(resolved, at: CGPoint(x: pt.x, y: pt.y))
    }

    private func drawCube(context: GraphicsContext, projector: Projector, position: SIMD3<Double>, quat: SIMD4<Double>, size: Double) {
        let h = size / 2
        let corners: [SIMD3<Double>] = [
            SIMD3(-h, -h, -h), SIMD3(h, -h, -h), SIMD3(h, h, -h), SIMD3(-h, h, -h),
            SIMD3(-h, -h, h), SIMD3(h, -h, h), SIMD3(h, h, h), SIMD3(-h, h, h)
        ].map { position + rotate(quat, $0) }
        let faces: [(indices: [Int], color: Color)] = [
            ([0, 1, 2, 3], Color(white: 0.12, opacity: 0.72)),
            ([4, 5, 6, 7], Color(white: 0.24, opacity: 0.72)),
            ([0, 1, 5, 4], Color(white: 0.18, opacity: 0.78)),
            ([1, 2, 6, 5], Color(white: 0.14, opacity: 0.78)),
            ([2, 3, 7, 6], Color(white: 0.22, opacity: 0.78)),
            ([3, 0, 4, 7], Color(white: 0.10, opacity: 0.78))
        ]
        let projectedFaces = faces.map { face -> (pts: [CGPoint], color: Color, depth: Double) in
            let pts = face.indices.map { projector.project(corners[$0]) }
            let depth = pts.reduce(0, { $0 + $1.depth }) / Double(pts.count)
            return (pts.map { CGPoint(x: $0.x, y: $0.y) }, face.color, depth)
        }.sorted { $0.depth > $1.depth }

        for face in projectedFaces {
            var p = Path()
            p.move(to: face.pts[0])
            for pt in face.pts.dropFirst() { p.addLine(to: pt) }
            p.closeSubpath()
            context.fill(p, with: .color(face.color))
            context.stroke(p, with: .color(.white.opacity(0.16)), lineWidth: 1)
        }

        let axisLen = size * 2.2
        let xEnd = position + rotate(quat, SIMD3(axisLen, 0, 0))
        let yEnd = position + rotate(quat, SIMD3(0, axisLen, 0))
        let zEnd = position + rotate(quat, SIMD3(0, 0, axisLen))
        line(context, projector, position, xEnd, axisColor("x"), 3)
        line(context, projector, position, yEnd, axisColor("y"), 3)
        line(context, projector, position, zEnd, axisColor("z"), 3)
        axisText(context, projector, xEnd, "w+X", axisColor("x"))
        axisText(context, projector, yEnd, "w+Y", axisColor("y"))
        axisText(context, projector, zEnd, "w+Z", axisColor("z"))
    }

    private func rotate(_ q: SIMD4<Double>, _ v: SIMD3<Double>) -> SIMD3<Double> {
        let vq = SIMD4(v.x, v.y, v.z, 0)
        let quatMul: (SIMD4<Double>, SIMD4<Double>) -> SIMD4<Double> = { a, b in
            let aq = SIMD3(a.x, a.y, a.z)
            let bq = SIMD3(b.x, b.y, b.z)
            let c = simd_cross(aq, bq) + b.w * aq + a.w * bq
            return SIMD4(c.x, c.y, c.z, a.w * b.w - simd_dot(aq, bq))
        }
        let conj: (SIMD4<Double>) -> SIMD4<Double> = { SIMD4(-$0.x, -$0.y, -$0.z, $0.w) }
        let r = quatMul(quatMul(q, vq), conj(q))
        return SIMD3(r.x, r.y, r.z)
    }

    private func bounds(of paths: [[SIMD3<Double>]]) -> (center: SIMD3<Double>, range: Double) {
        var minV = SIMD3(Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude)
        var maxV = SIMD3(-Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude)
        var count = 0
        for path in paths {
            for p in path {
                minV = simd_min(minV, p)
                maxV = simd_max(maxV, p)
                count += 1
            }
        }
        if count == 0 { return (SIMD3(0, 0, 0), 1) }
        let center = (minV + maxV) * 0.5
        let range = max(max(maxV.x - minV.x, maxV.y - minV.y), max(maxV.z - minV.z, 0.08))
        return (center, range)
    }

    private func niceStep(_ range: Double) -> Double {
        let rough = max(range / 5, 1e-9)
        let pow10 = pow(10, floor(log10(rough)))
        let scaled = rough / pow10
        if scaled < 1.5 { return pow10 }
        if scaled < 3.5 { return 2 * pow10 }
        if scaled < 7.5 { return 5 * pow10 }
        return 10 * pow10
    }

    private func axisColor(_ axis: String) -> Color {
        switch axis {
        case "x": return Color(red: 1.0, green: 0.41, blue: 0.41)
        case "z": return Color(red: 0.46, green: 0.65, blue: 1.0)
        default: return Color(red: 0.19, green: 0.76, blue: 0.44)
        }
    }
}
