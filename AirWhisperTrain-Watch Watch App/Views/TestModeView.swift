import SwiftUI

struct TestModeView: View {
    @Bindable var viewModel: TestViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            
            // 80% area - Large predicted letter with confidence / top 5 list
            VStack(spacing: 8) {
                // Main letter display
                Text(viewModel.predictedLetter.isEmpty ? "-" : viewModel.predictedLetter)
                    .font(.system(size: WatchConstants.testLetterFontSize, weight: .black))
                    .foregroundStyle(.white)
                
                // Confidence or initial state
                if viewModel.top5Predictions.isEmpty && !viewModel.isRecording {
                    Text("0%")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if !viewModel.top5Predictions.isEmpty {
                    // Top 5 predictions list
                    VStack(spacing: 4) {
                        ForEach(Array(viewModel.top5Predictions.enumerated()), id: \.offset) { index, prediction in
                            HStack {
                                Text("\(index + 1). \(prediction.0)")
                                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(Int(prediction.1 * 100))%")
                                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.blue)
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                } else {
                    Text("\(Int(viewModel.confidence * 100))%")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: .infinity)
            
            Spacer()
            
            // 20% area - Start/Stop button for inference
            VStack(spacing: 8) {
                // Timer always visible - zeroed when idle, shows elapsed when recording or after stop
                Text(WatchFormatters.elapsedText(viewModel.elapsed))
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(viewModel.isRecording ? .red : .primary)
                    .animation(.default, value: viewModel.elapsed)
                
                Button {
                    if viewModel.isRecording {
                        viewModel.stopRecording()
                    } else {
                        viewModel.startRecording()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                            .font(.title3)
                        Text(viewModel.isRecording ? "Stop & Predict" : "Start Writing")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WatchConstants.buttonVerticalPadding)
                    .background(viewModel.isRecording ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
                    .foregroundStyle(viewModel.isRecording ? .red : .blue)
                    .clipShape(.rect(cornerRadius: WatchConstants.buttonCornerRadius))
                    .glassEffect(in: .rect(cornerRadius: WatchConstants.buttonCornerRadius))
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.recorder.isDeviceMotionAvailable)
                .padding(.horizontal, WatchConstants.horizontalPaddingWide)
                .accessibilityLabel(viewModel.isRecording ? "Stop and predict" : "Start writing")
                .accessibilityHint(viewModel.isRecording ? "Tap to stop writing and get prediction" : "Tap to start writing in the air for prediction")
            }
            
            Text(viewModel.recorder.isDeviceMotionAvailable ? (viewModel.isRecording ? "Writing…" : "Tap to start") : "Motion unavailable")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(height: 14)
        }
        .padding(.horizontal, WatchConstants.horizontalPadding)
    }
}