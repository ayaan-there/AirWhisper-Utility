import SwiftUI

struct VisualizationOverviewScreen: View {

    @ObservedObject var model: AppModel
    let letter: String

    private var recordings: [IMURecording] {
        model.store.recordings(for: letter)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(recordings) { rec in
                    NavigationLink(value: rec) {
                        HStack {
                            Image(systemName: "chart.xyaxis.line")
                                .foregroundStyle(AppTheme.brandBlue)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rec.label)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(rec.samples.count) samples · \(String(format: "%.1fs", rec.duration))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\(letter) Overview")
        .navigationBarTitleDisplayMode(.inline)
    }
}
