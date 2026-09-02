import Foundation
import simd

struct MotionSample: Codable, Equatable, Hashable {
    let timestamp: Double
    let rotationRateX: Double
    let rotationRateY: Double
    let rotationRateZ: Double
    let gravityX: Double
    let rotationRateY: Double
    let rotationRateZ: Double
    let gravityX: Double
    let gravityY: Double
    let gravityZ: Double
    let accelerationX: Double
    let accelerationY: Double
    let accelerationZ: Double
    let quaternionW: Double
    let quaternionX: Double
    let quaternionY: Double
    let quaternionZ: Double

    /// Quaternion as SIMD4 for rotation math
    var quaternion: SIMD4<Double> {
        SIMD4(quaternionW, quaternionX, quaternionY, quaternionZ)
    }

    /// User acceleration as SIMD3
    var userAcceleration: SIMD3<Double> {
        SIMD3(accelerationX, accelerationY, accelerationZ)
    }

    /// Gravity vector as SIMD3
    var gravity: SIMD3<Double> {
        SIMD3(gravityX, gravityY, gravityZ)
    }

    /// Rotation rate as SIMD3
    var rotationRate: SIMD3<Double> {
        SIMD3(rotationRateX, rotationRateY, rotationRateZ)
    }

    /// Rotate user acceleration to world frame using quaternion
    /// World acceleration = q * userAccel * q⁻¹ (where q⁻¹ = conjugate for unit quaternion)
    func accelerationWorld() -> SIMD3<Double> {
        let q = simd_normalize(quaternion)
        let v = userAcceleration
        let vq = SIMD4(v.x, v.y, v.z, 0)
        let qConj = SIMD4(-q.x, -q.y, -q.z, q.w)
        let r = quatMul(quatMul(q, vq), qConj)
        return SIMD3(r.x, r.y, r.z)
    }

    /// Gyro energy (magnitude squared of rotation rate)
    var gyroEnergy: Double {
        rotationRateX * rotationRateX + rotationRateY * rotationRateY + rotationRateZ * rotationRateZ
    }

    /// Acceleration energy in world frame (computed lazily)
    func accEnergy(worldAccel: SIMD3<Double>) -> Double {
        worldAccel.x * worldAccel.x + worldAccel.y * worldAccel.y + worldAccel.z * worldAccel.z
    }
}

/// Quaternion multiplication
private func quatMul(_ a: SIMD4<Double>, _ b: SIMD4<Double>) -> SIMD4<Double> {
    let aq = SIMD3(a.x, a.y, a.z)
    let bq = SIMD3(b.x, b.y, b.z)
    let c = simd_cross(aq, bq) + b.w * aq + a.w * bq
    return SIMD4(c.x, c.y, c.z, a.w * b.w - simd_dot(aq, bq))
}

/// Feature extraction for server upload (15 features × 384 timesteps)
extension MotionSample {
    /// Compute the 15-feature vector for a single sample given context
    /// - Parameters:
    ///   - worldAccel: Precomputed world-frame acceleration
    ///   - energyProgress: Normalized time index (0.0 to 1.0)
    ///   - prevSample: Previous sample for delta computation (nil for first)
    /// - Returns: Array of 15 Float features
    func featureVector(
        worldAccel: SIMD3<Double>,
        energyProgress: Float,
        prevSample: MotionSample?
    ) -> [Float] {
        let deltaGyro: SIMD3<Double>
        let deltaAccelWorld: SIMD3<Double>

        if let prev = prevSample {
            let prevWorldAccel = prev.accelerationWorld()
            deltaGyro = rotationRate - prev.rotationRate
            deltaAccelWorld = worldAccel - prevWorldAccel
        } else {
            deltaGyro = .zero
            deltaAccelWorld = .zero
        }

        let accEnergy = accEnergy(worldAccel: worldAccel)

        return [
            Float(rotationRateX), Float(rotationRateY), Float(rotationRateZ),
            Float(worldAccel.x), Float(worldAccel.y), Float(worldAccel.z),
            Float(gyroEnergy), Float(accEnergy), energyProgress,
            Float(deltaGyro.x), Float(deltaGyro.y), Float(deltaGyro.z),
            Float(deltaAccelWorld.x), Float(deltaAccelWorld.y), Float(deltaAccelWorld.z)
        ]
    }

    /// Extract features from an array of samples, padding/truncating to 384 timesteps
    static func extractFeatures(from samples: [MotionSample], targetLength: Int = 384) -> [Float] {
        guard !samples.isEmpty else { return Array(repeating: 0, count: targetLength * 15) }

        // Precompute world accelerations
        let worldAccels = samples.map { $0.accelerationWorld() }

        var featureMatrix: [[Float]] = []
        for (i, sample) in samples.enumerated() {
            let progress = samples.count > 1 ? Float(i) / Float(samples.count - 1) : 0.5
            let prev = i > 0 ? samples[i - 1] : nil
            featureMatrix.append(sample.featureVector(
                worldAccel: worldAccels[i],
                energyProgress: progress,
                prevSample: prev
            ))
        }

        // Pad or truncate to target length
        if featureMatrix.count > targetLength {
            featureMatrix = Array(featureMatrix.prefix(targetLength))
        } else if featureMatrix.count < targetLength {
            let padding = Array(repeating: [Float](repeating: 0, count: 15), count: targetLength - featureMatrix.count)
            featureMatrix.append(contentsOf: padding)
        }

        return featureMatrix.flatMap { $0 }
    }
}
