import SwiftUI

struct VisualizationScreen: View {

    let recording: IMURecording

    private var viz: IMAVisualizer {
        IMAVisualizer(samples: recording.samples, name: recording.label)
    }

    @State private var mode: String = "world"
    @State private var frame: Double = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let drawing = recording.drawing {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How \(recording.label) was drawn")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal)
                        DrawingReplayView(pattern: drawing)
                            .padding(.horizontal)
                    }
                }
                IMASceneView(viz: viz, mode: $mode, frame: $frame)
                IMAAccelPlotView(viz: viz, mode: $mode, frame: $frame)
                    .padding(.horizontal)
                IMAInsightsView(viz: viz)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(recording.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}
