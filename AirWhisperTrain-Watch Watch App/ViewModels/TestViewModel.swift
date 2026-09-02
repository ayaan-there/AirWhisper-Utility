import Foundation
import Observation
import Combine

@Observable
@MainActor
final class TestViewModel {
    // State
    var predictedLetter: String = ""
    var confidence: Float = 0.0
    var top5Predictions: [(String, Float)] = []
    var isRecording: Bool = false
    var elapsed: TimeInterval = 0
    var recorder: AirWriteMotionRecorder
    
    // Dependencies
    private let inferenceService: InferenceService
    private let timerInterval: TimeInterval = 0.1
    private var timerTask: Task<Void, Never>?
    
    init(recorder: AirWriteMotionRecorder, inferenceService: InferenceService) {
        self.recorder = recorder
        self.inferenceService = inferenceService
    }
    
    func startRecording() {
        guard recorder.isDeviceMotionAvailable else { return }
        elapsed = 0
        predictedLetter = ""
        confidence = 0.0
        top5Predictions = []
        isRecording = true
        recorder.startRecording(letter: "TEST", expectedIndex: 0)
        startTimer()
    }
    
    func stopRecording() {
        isRecording = false
        stopTimer()
        
        let result = recorder.stopRecording()
        guard !result.samples.isEmpty else { return }
        
        Task {
            await runInference(samples: result.samples)
        }
        // Don't reset elapsed - persist until next start
    }
    
    private func runInference(samples: [MotionSample]) async {
        do {
            let features = MotionSample.extractFeatures(from: samples)
            let response = try await inferenceService.predict(features: features)
            
            predictedLetter = response.letter
            confidence = response.confidence
            top5Predictions = response.top5.map { ($0.letter, $0.prob) }
        } catch {
            print("[TestViewModel] Inference failed: \(error)")
        }
    }
    
    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(timerInterval))
                if isRecording {
                    elapsed += timerInterval
                }
            }
        }
    }
    
    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }
}