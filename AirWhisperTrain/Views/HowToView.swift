import SwiftUI

struct HowToView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(systemImage: String, title: String, detail: String)] = [
        ("square.grid.3x3", "Pick a letter", "Choose one of the 26 letters from the grid on the home screen."),
        ("pencil.and.outline", "Draw it on screen", "Trace the letter on the blank slate. Use pen, erase, thickness, undo and redo until it looks right."),
        ("hand.draw", "Record in the air", "On your Apple Watch, tap Start and physically draw the letter in the air while wearing it. Tap Stop when done."),
        ("arrow.up.forward.app", "Review on iPhone", "Each sample arrives on your iPhone as A1, A2, A3… Tap any one to see its 3D IMU visualization and insights."),
        ("waveform.path.ecg", "Repeat 40 times", "Keep recording until you reach 40 samples for that letter."),
        ("checkmark.circle.fill", "Submit dataset", "At 40/40, the blue Submit button unlocks at the bottom of the screen."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    VStack(spacing: 12) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            stepRow(index: index + 1, step: step)
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("How to use")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.draw")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.brandBlue)
            Text("How to use — Air Write")
                .font(.title2.weight(.bold))
            Text("Collect 40 IMU samples per letter by drawing the shape in the air while wearing your Apple Watch.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private func stepRow(index: Int, step: (systemImage: String, title: String, detail: String)) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.brandBlue.opacity(0.14))
                Image(systemName: step.systemImage)
                    .font(.title3)
                    .foregroundStyle(AppTheme.brandBlue)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(index). \(step.title)")
                    .font(.subheadline.weight(.semibold))
                Text(step.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
