import Foundation
import simd

/// Swift port of the reference `airwhisper_imu_visualizer.html` computation
/// (device / world / start / plane45 coordinate modes, drift-controlled
/// double integration, axis energy, rough plane fit and angle metrics).
struct IMAVisualizer {

    let name: String
    let duration: Double
    let sampleRateHz: Double
    let rows: Int
    let initialGravity: SIMD3<Double>
    let gravityAngleFromStraight: Double
    let axisEnergyPercent: [Double]
    let dominantRawAxis: String
    let rawToWorldDiagRatio: Double
    let extents: [String: SIMD3<Double>]
    let time: [Double]
    let accel: [String: [SIMD3<Double>]]
    let paths: [String: [SIMD3<Double>]]
    let quaternions: [String: [SIMD4<Double>]]
    let planeNormal: SIMD3<Double>
    let planeMajorAxis: SIMD3<Double>
    let planeMinorAxis: SIMD3<Double>
    let gesturePath: [SIMD3<Double>]

    private static let toRad = Double.pi / 180.0

    init(samples: [MotionSample], name: String = "Recording") {
        self.name = name
        let rows = samples
        self.rows = rows.count

        var times = [Double]()
        let t0 = rows.first?.timestamp ?? 0
        for s in rows { times.append(s.timestamp - t0) }
        self.time = times
        let duration = times.last ?? 0
        self.duration = duration

        let quats: [SIMD4<Double>] = rows.map { simd_normalize(SIMD4($0.quaternionW, $0.quaternionX, $0.quaternionY, $0.quaternionZ)) }
        let accelDevice: [SIMD3<Double>] = rows.map { SIMD3($0.accelerationX, $0.accelerationY, $0.accelerationZ) }
        let accelWorld = rows.enumerated().map { i, _ in Self.rotate(quats[i], accelDevice[i]) }

        let q0Conj = Self.quatConj(quats.first ?? SIMD4(1, 0, 0, 0))
        let accelStart = accelWorld.map { Self.rotate(q0Conj, $0) }
        let quatsStart: [SIMD4<Double>] = quats.map { simd_normalize(Self.quatMul(q0Conj, $0)) }

        let paths: [String: [SIMD3<Double>]] = [
            "device": Self.integrateDriftControlled(times, accelDevice),
            "world": Self.integrateDriftControlled(times, accelWorld),
            "start": Self.integrateDriftControlled(times, accelStart)
        ]
        let plane45 = paths["world"] ?? []
        let gesturePath = plane45

        let extents: [String: SIMD3<Double>] = paths.mapValues { Self.pathExtent($0) }
        let initialGravity = SIMD3(rows.first?.gravityX ?? 0, rows.first?.gravityY ?? 0, rows.first?.gravityZ ?? 0)
        let referenceGravity = SIMD3<Double>(0, 0, -1)
        let axisEnergy = Self.axisEnergyPercent(accelDevice)
        let dominantRawAxis = ["X", "Y", "Z"][axisEnergy.firstIndex(of: axisEnergy.max() ?? 0) ?? 0]
        let rawDiag = sqrt(extents["device"]!.x * extents["device"]!.x + extents["device"]!.y * extents["device"]!.y + extents["device"]!.z * extents["device"]!.z)
        let worldDiag = sqrt(extents["world"]!.x * extents["world"]!.x + extents["world"]!.y * extents["world"]!.y + extents["world"]!.z * extents["world"]!.z)
        let plane = Self.roughPlane(paths["world"] ?? [])

        self.initialGravity = initialGravity
        self.gravityAngleFromStraight = Self.angleBetween(initialGravity, referenceGravity)
        self.axisEnergyPercent = axisEnergy
        self.dominantRawAxis = dominantRawAxis
        self.rawToWorldDiagRatio = worldDiag > 0 ? rawDiag / worldDiag : 0
        self.extents = extents
        self.accel = [
            "device": accelDevice,
            "world": accelWorld,
            "start": accelStart,
            "plane45": accelWorld
        ]
        self.paths = paths
        self.quaternions = [
            "world": quats,
            "start": quatsStart,
            "plane45": quats
        ]
        self.planeNormal = plane.normal
        self.planeMajorAxis = plane.majorAxis
        self.planeMinorAxis = plane.minorAxis
        self.gesturePath = gesturePath

        let dt = Self.typicalDt(times)
        if dt > 0 {
            self.sampleRateHz = 1.0 / dt
        } else {
            self.sampleRateHz = 0
        }
    }

    // MARK: - Coordinate mode accessors

    func path(for mode: String) -> [SIMD3<Double>] {
        paths[mode] ?? paths["world"] ?? []
    }

    func accel(for mode: String) -> [SIMD3<Double>] {
        accel[mode] ?? accel["world"] ?? []
    }

    func quaternions(for mode: String) -> [SIMD4<Double>] {
        quaternions[mode] ?? quaternions["world"] ?? []
    }

    static let modeNames = ["world", "start", "device", "plane45"]

    static func modeLabel(_ mode: String) -> String {
        switch mode {
        case "device": return "raw sensor axes"
        case "start": return "start-normalized"
        case "plane45": return "aligned to plane"
        default: return "quaternion world frame"
        }
    }

    // MARK: - Quaternion helpers

    private static func quatMul(_ a: SIMD4<Double>, _ b: SIMD4<Double>) -> SIMD4<Double> {
        let aq = SIMD3(a.x, a.y, a.z)
        let bq = SIMD3(b.x, b.y, b.z)
        let c = simd_cross(aq, bq) + b.w * aq + a.w * bq
        return SIMD4(c.x, c.y, c.z, a.w * b.w - simd_dot(aq, bq))
    }

    private static func quatConj(_ q: SIMD4<Double>) -> SIMD4<Double> {
        SIMD4(-q.x, -q.y, -q.z, q.w)
    }

    private static func rotate(_ q: SIMD4<Double>, _ v: SIMD3<Double>) -> SIMD3<Double> {
        let vq = SIMD4(v.x, v.y, v.z, 0)
        let r = quatMul(quatMul(q, vq), quatConj(q))
        return SIMD3(r.x, r.y, r.z)
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private static func movingAverage(_ values: [Double], _ window: Int) -> [Double] {
        let n = values.count
        guard n > 0 else { return [] }
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let lo = max(0, i - (window - 1) / 2)
            let hi = min(n - 1, i + window / 2)
            var sum = 0.0
            var count = 0.0
            for j in lo...hi {
                sum += values[j]
                count += 1
            }
            out[i] = sum / count
        }
        return out
    }

    private static func movingAverageRows(_ rows: [SIMD3<Double>], _ window: Int) -> [SIMD3<Double>] {
        let xs = movingAverage(rows.map(\.x), window)
        let ys = movingAverage(rows.map(\.y), window)
        let zs = movingAverage(rows.map(\.z), window)
        return (0..<rows.count).map { SIMD3(xs[$0], ys[$0], zs[$0]) }
    }

    private static func typicalDt(_ times: [Double]) -> Double {
        guard times.count > 1 else { return 0.01 }
        let d = times.count - 1
        var sum = 0.0
        var count = 0
        for i in 1...d {
            let dt = times[i] - times[i - 1]
            if dt > 0 && dt <= 0.1 {
                sum += dt
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : (times[d] - times[0]) / Double(d)
    }

    private static func integrateDriftControlled(_ times: [Double], _ accelG: [SIMD3<Double>]) -> [SIMD3<Double>] {
        let n = times.count
        if n == 0 { return [] }
        if n == 1 { return [SIMD3(0, 0, 0)] }
        let smoothed = movingAverageRows(accelG, 5)
        let edge = max(10, min(40, n / 8))
        var endpointIds = [Int]()
        for i in 0..<min(edge, n) { endpointIds.append(i) }
        for i in max(edge, n - edge)..<n { endpointIds.append(i) }

        var bias = SIMD3<Double>(0, 0, 0)
        for axis in 0..<3 {
            let vals = endpointIds.map { smoothed[$0][axis] }
            bias[axis] = median(vals)
        }
        let accel = smoothed.map { ($0 - bias) * 9.80665 }
        let fallbackDt = typicalDt(times)

        var velocity = [SIMD3<Double>](repeating: .zero, count: n)
        for i in 1..<n {
            var dt = times[i] - times[i - 1]
            if dt <= 0 || dt > 0.1 { dt = fallbackDt }
            velocity[i] = velocity[i - 1] + 0.5 * (accel[i] + accel[i - 1]) * dt
        }
        let duration = max(times[n - 1], fallbackDt)
        let corrected = velocity.enumerated().map { i, v in
            let f = (i > 0 ? times[i] : 0) / duration
            return v - velocity[n - 1] * f
        }
        var position = [SIMD3<Double>](repeating: .zero, count: n)
        for i in 1..<n {
            var dt = times[i] - times[i - 1]
            if dt <= 0 || dt > 0.1 { dt = fallbackDt }
            position[i] = position[i - 1] + 0.5 * (corrected[i] + corrected[i - 1]) * dt
        }
        let mean = position.reduce(SIMD3(0, 0, 0), +) / Double(n)
        return position.map { $0 - mean }
    }

    private static func pathExtent(_ path: [SIMD3<Double>]) -> SIMD3<Double> {
        guard let first = path.first else { return .zero }
        var minV = first
        var maxV = first
        for p in path {
            minV = simd_min(minV, p)
            maxV = simd_max(maxV, p)
        }
        return maxV - minV
    }

    private static func axisEnergyPercent(_ accel: [SIMD3<Double>]) -> [Double] {
        var energy = [0.0, 0.0, 0.0]
        for v in accel {
            energy[0] += v.x * v.x
            energy[1] += v.y * v.y
            energy[2] += v.z * v.z
        }
        let total = energy.reduce(0, +)
        let denom = total > 0 ? total : 1
        return energy.map { 100 * $0 / denom }
    }

    private static func angleBetween(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let magA = simd_length(a)
        let magB = simd_length(b)
        if magA < 1e-12 || magB < 1e-12 { return 0 }
        let cos = simd_clamp(simd_dot(a, b) / (magA * magB), -1, 1)
        return acos(cos) / toRad
    }

    private static func roughPlane(_ path: [SIMD3<Double>]) -> (normal: SIMD3<Double>, majorAxis: SIMD3<Double>, minorAxis: SIMD3<Double>) {
        if path.count < 3 {
            return (SIMD3(0, 0, 1), SIMD3(1, 0, 0), SIMD3(0, 1, 0))
        }
        let a = path[path.count * 1 / 2] - path[0]
        let b = path[path.count - 1] - path[0]
        var n = simd_normalize(simd_cross(a, b))
        if simd_length(simd_cross(a, b)) < 1e-9 { n = SIMD3(0, 0, 1) }
        var u = simd_normalize(b)
        if simd_length(b) < 1e-9 { u = SIMD3(1, 0, 0) }
        var v = simd_normalize(simd_cross(n, u))
        if simd_length(simd_cross(n, u)) < 1e-9 { v = SIMD3(0, 1, 0) }
        return (n, u, v)
    }
}
