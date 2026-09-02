import SwiftUI

struct TrainModeView: View {
    @Bindable var viewModel: TrainViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            
            // 80% area - Letter and sample count
            VStack(spacing: 8) {
                Text(viewModel.letter)
                    .font(.system(size: WatchConstants.letterFontSize, weight: .black))
                    .foregroundStyle(.white)
                
                Text("Sample \(viewModel.expectedIndex) of \(WatchConstants.expectedSamplesPerLetter)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                
                Text("\(viewModel.sampleCount) / \(WatchConstants.maxSamplesPerLetter) total")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                
                ProgressView(value: Double(viewModel.sampleCount), total: Double(WatchConstants.maxSamplesPerLetter))
                    .tint(.green)
                    .padding(.horizontal, 20)
                
                // Timer always visible - shows last elapsed time
                Text(WatchFormatters.elapsedText(viewModel.elapsed))
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .animation(.default, value: viewModel.elapsed)
            }
            .frame(maxHeight: .infinity)
            
            Spacer()
            
            // 20% area - Start/Stop button with timer above it
            VStack(spacing: 8) {
                // Timer displayed near button (large font)
                Text(WatchFormatters.elapsedText(viewModel.elapsed))
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .animation(.default, value: viewModel.elapsed)
                
                Button {
                    if viewModel.isRecording {
                        viewModel.stopRecording()
                    } else {
                        viewModel.startRecording()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.isRecording ? "stop.fill" : "record.circle")
                            .font(.title3)
                        Text(viewModel.isRecording ? "Stop Recording" : "Start Recording")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WatchConstants.buttonVerticalPadding)
                    .background(viewModel.isRecording ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                    .foregroundStyle(viewModel.isRecording ? .red : .green)
                    .clipShape(.rect(cornerRadius: WatchConstants.buttonCornerRadius))
                    .glassEffect(in: .rect(cornerRadius: WatchConstants.buttonCornerRadius))
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.recorder.isDeviceMotionAvailable)
                .padding(.horizontal, WatchConstants.horizontalPaddingWide)
                .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start recording")
                .accessibilityHint(viewModel.isRecording ? "Tap to stop recording the current sample" : "Tap to start recording a new sample")
            }
            
            Text(viewModel.recorder.isDeviceMotionAvailable ? (viewModel.isRecording ? "Recording… keep moving" : "Ready") : "Motion unavailable")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(height: 14)
        }
        .padding(.horizontal, WatchConstants.horizontalPadding)
    }
}