import Foundation
import Observation
import Combine

@Observable
@MainActor
final class TrainViewModel {
    // State
    var letter: String = "?"
    var sampleCount: Int = 0
    var expectedIndex: Int = 1
    var isRecording: Bool = false
    var elapsed: TimeInterval = 0
    var recorder: AirWriteMotionRecorder
    
    // Dependencies
    private let connectivity: TrainWatchConnectivityClient
    private let timerInterval: TimeInterval = 0.1
    private var timerTask: Task<Void, Never>?
    
    init(connectivity: TrainWatchConnectivityClient, recorder: AirWriteMotionRecorder) {
        self.connectivity = connectivity
        self.recorder = recorder
    }
    
    func startRecording() {
        guard let letter = connectivity.currentLetter else { return }
        guard recorder.isDeviceMotionAvailable else { return }
        elapsed = 0
        isRecording = true
        recorder.startRecording(letter: letter, expectedIndex: expectedIndex)
        startTimer()
    }
    
    func stopRecording() {
        isRecording = false
        stopTimer()
        
        let result = recorder.stopRecording()
        guard let letter = connectivity.currentLetter, !result.samples.isEmpty else { return }
        
        let recording = IMURecording(
            id: UUID(),
            letter: letter,
            index: expectedIndex,
            duration: result.duration,
            samples: result.samples
        )
        connectivity.sendRecording(recording)
        // Don't reset elapsed - persist until next start
        sampleCount = min(sampleCount + 1, 100)
    }
    
    func updateLetter(_ letter: String) {
        self.letter = letter
    }
    
    func updateExpectedIndex(_ index: Int) {
        self.expectedIndex = index
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