import SwiftUI
import Combine

struct RecordingView: View {

    @EnvironmentObject private var connectivity: TrainWatchConnectivityClient
    @StateObject private var recorder = AirWriteMotionRecorder()

    @State private var elapsed: TimeInterval = 0
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Text(connectivity.currentLetter ?? "?")
                .font(.system(size: 72, weight: .black))
                .foregroundStyle(.green)

            Text("Recording \(connectivity.expectedIndex) of 40")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(elapsedText)
                .font(.system(size: 28, weight: .medium, design: .monospaced))
                .contentTransition(.numericText())

            Spacer()

            recordButton

            Text(recorder.isRecording ? "Recording… keep moving" : "Ready")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(height: 14)
        }
        .padding(.horizontal, 12)
        .onAppear {
            connectivity.setReachableState()
        }
        .onReceive(timer) { _ in
            if recorder.isRecording {
                elapsed += 0.1
            }
        }
        .onDisappear {
            if recorder.isRecording {
                _ = recorder.stopRecording()
            }
        }
    }

    private var recordButton: some View {
        Button {
            if recorder.isRecording {
                stopAndSend()
            } else {
                start()
            }
        } label: {
            ActionLabel(
                title: recorder.isRecording ? "Stop" : "Start",
                systemImage: recorder.isRecording ? "stop.fill" : "record.circle",
                color: recorder.isRecording ? .red.opacity(0.35) : .green.opacity(0.35)
            )
        }
        .buttonStyle(.plain)
    }

    private func start() {
        guard let letter = connectivity.currentLetter else { return }
        guard recorder.isDeviceMotionAvailable else { return }
        elapsed = 0
        recorder.startRecording(letter: letter, expectedIndex: connectivity.expectedIndex)
    }

    private func stopAndSend() {
        let result = recorder.stopRecording()
        guard let letter = connectivity.currentLetter, !result.samples.isEmpty else { return }
        let recording = IMURecording(
            id: UUID(),
            letter: letter,
            index: connectivity.expectedIndex,
            duration: result.duration,
            samples: result.samples
        )
        connectivity.sendRecording(recording)
        elapsed = 0
    }
}

extension RecordingView {
    private var elapsedText: String {
        let total = Int(elapsed)
        let m = total / 60
        let s = total % 60
        let tenths = Int((elapsed - Double(total)) * 10)
        return String(format: "%02d:%02d.%01d", m, s, tenths)
    }
}

private struct ActionLabel: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
            Text(title)
                .font(.body.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .glassEffect(in: .rect(cornerRadius: 16))
    }
}
