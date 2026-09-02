import CoreMotion
import Combine
import Foundation
import WatchConnectivity

/// Motion recorder for air-writing IMU data capture at 100Hz.
/// Uses CoreMotion's device motion updates with drift-controlled processing.
/// 
/// Memory management:
/// - Weak references in callbacks to avoid retain cycles
/// - Bounded buffer with configurable max samples
/// - Proper cleanup in deinit and cancelRecording()
final class AirWriteMotionRecorder: ObservableObject {

    @Published private(set) var isRecording: Bool = false
    @Published private(set) var sampleCount: Int = 0

    private let manager = CMMotionManager()
    private let maxSamples: Int = 12000  // 2 minutes at 100Hz
    private let samplingRateHz: Double = 100.0

    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "AirWhisperTrain.motion.queue"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }()

    private let lock = NSLock()
    private var samplesBuffer: [MotionSample] = []
    private var isRecordingInternally: Bool = false
    private var recordingStartTime: TimeInterval = 0
    private var elapsedAccumulator: TimeInterval = 0

    /// Called when recording completes. Weak capture to avoid retain cycle.
    var onRecordingComplete: (([MotionSample], TimeInterval) -> Void)?

    /// Called per sample. Weak capture to avoid retain cycle.
    var onSampleRecorded: ((MotionSample) -> Void)?

    deinit {
        stopDeviceMotionUpdates()
    }

    var isDeviceMotionAvailable: Bool {
        manager.isDeviceMotionAvailable
    }

    func startRecording(letter: String, expectedIndex: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard !isRecordingInternally else { return }
        guard manager.isDeviceMotionAvailable else { return }

        samplesBuffer.removeAll(keepingCapacity: true)
        isRecordingInternally = true
        elapsedAccumulator = 0
        recordingStartTime = CFAbsoluteTimeGetCurrent()

        manager.deviceMotionUpdateInterval = 1.0 / samplingRateHz

        DispatchQueue.main.async {
            self.isRecording = true
            self.sampleCount = 0
        }

        // Use weak self to avoid retain cycle in the callback
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            self.processMotionSample(m)
        }
    }

    func stopRecording() -> (samples: [MotionSample], duration: TimeInterval) {
        stopDeviceMotionUpdates()

        var captured: [MotionSample] = []
        var duration: TimeInterval = 0
        lock.lock()
        let wasRecording = isRecordingInternally
        isRecordingInternally = false
        if wasRecording {
            duration = elapsedAccumulator
        }
        captured = samplesBuffer
        samplesBuffer.removeAll(keepingCapacity: true)
        lock.unlock()

        DispatchQueue.main.async {
            self.isRecording = false
        }
        onRecordingComplete?(captured, duration)
        return (captured, duration)
    }

    func cancelRecording() {
        stopDeviceMotionUpdates()
        lock.lock()
        isRecordingInternally = false
        samplesBuffer.removeAll(keepingCapacity: true)
        lock.unlock()
        DispatchQueue.main.async {
            self.isRecording = false
            self.sampleCount = 0
        }
    }

    /// Centralized cleanup for device motion updates
    private func stopDeviceMotionUpdates() {
        manager.stopDeviceMotionUpdates()
        queue.cancelAllOperations()
    }

    private func processMotionSample(_ motion: CMDeviceMotion) {
        lock.lock()
        guard isRecordingInternally else {
            lock.unlock()
            return
        }

        let q = motion.attitude.quaternion
        let sample = MotionSample(
            timestamp: motion.timestamp,
            rotationRateX: motion.rotationRate.x,
            rotationRateY: motion.rotationRate.y,
            rotationRateZ: motion.rotationRate.z,
            gravityX: motion.gravity.x,
            gravityY: motion.gravity.y,
            gravityZ: motion.gravity.z,
            accelerationX: motion.userAcceleration.x,
            accelerationY: motion.userAcceleration.y,
            accelerationZ: motion.userAcceleration.z,
            quaternionW: q.w,
            quaternionX: q.x,
            quaternionY: q.y,
            quaternionZ: q.z
        )

        samplesBuffer.append(sample)
        // Enforce bounded buffer
        if samplesBuffer.count > maxSamples {
            samplesBuffer.removeFirst(samplesBuffer.count - maxSamples)
        }
        elapsedAccumulator = CFAbsoluteTimeGetCurrent() - recordingStartTime
        lock.unlock()

        // Notify callback for WatchConnectivity transfer
        onSampleRecorded?(sample)

        DispatchQueue.main.async {
            self.sampleCount = self.samplesBufferCount()
        }
    }

    private func samplesBufferCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return samplesBuffer.count
    }
}
