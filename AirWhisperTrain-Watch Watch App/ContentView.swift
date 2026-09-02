import SwiftUI
import Observation

// Watch app constants - shared across all Watch views
enum WatchConstants {
    static let maxSamplesPerLetter = 100
    static let expectedSamplesPerLetter = 40
    static let timerInterval: TimeInterval = 0.1
    static let letterFontSize: CGFloat = 72
    static let testLetterFontSize: CGFloat = 96
    static let buttonCornerRadius: CGFloat = 16
    static let buttonVerticalPadding: CGFloat = 16
    static let horizontalPadding: CGFloat = 12
    static let horizontalPaddingWide: CGFloat = 16
}

struct ContentView: View {
    @EnvironmentObject private var connectivity: TrainWatchConnectivityClient
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var selectedMode: WatchMode?
    
    // View models - owned by ContentView, injected into child views
    @State private var trainViewModel: TrainViewModel
    @State private var testViewModel: TestViewModel
    
    // Inference service shared between test view models
    @State private var inferenceService = InferenceService()
    
    init() {
        let trainRecorder = AirWriteMotionRecorder()
        let testRecorder = AirWriteMotionRecorder()
        let inferenceService = InferenceService()
        _trainViewModel = State(initialValue: TrainViewModel(connectivity: TrainWatchConnectivityClient.shared, recorder: trainRecorder))
        _testViewModel = State(initialValue: TestViewModel(recorder: testRecorder, inferenceService: inferenceService))
        _inferenceService = State(initialValue: inferenceService)
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if let mode = selectedMode {
                    switch mode {
                    case .train:
                        TrainModeView(viewModel: trainViewModel)
                    case .test:
                        TestModeView(viewModel: testViewModel)
                    }
                } else {
                    ModeSelectionView(onSelect: { mode in
                        selectedMode = mode
                        if mode == .train {
                            connectivity.requestCurrentState()
                        }
                    })
                }
            }
            .toolbar {
                if selectedMode != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            if trainViewModel.isRecording { trainViewModel.stopRecording() }
                            if testViewModel.isRecording { testViewModel.stopRecording() }
                            selectedMode = nil
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
            }
            .onAppear {
                connectivity.requestCurrentState()
                connectivity.setReachableState()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    connectivity.requestCurrentState()
                    connectivity.setReachableState()
                }
            }
            .onReceive(connectivity.$currentLetter) { letter in
                if selectedMode == .train, let letter {
                    trainViewModel.updateLetter(letter)
                }
            }
            .onReceive(connectivity.$expectedIndex) { index in
                if selectedMode == .train {
                    trainViewModel.updateExpectedIndex(index)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(TrainWatchConnectivityClient.shared)
}
