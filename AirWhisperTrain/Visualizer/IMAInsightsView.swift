import SwiftUI
import simd

/// Readout of computed IMU insights, porting the reference visualizer's key
/// statistics (energy split, gravity angle, drift ratio, extents, plane).
struct IMAInsightsView: View {

    let viz: IMAVisualizer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insights")
                .font(.headline)

            energyCard

            readoutGrid

            planeCard
        }
    }

    private var energyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Axis energy split (raw)")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 16) {
                energyBar(percent: viz.axisEnergyPercent[0], color: AppTheme.brandBlue, label: "X")
                energyBar(percent: viz.axisEnergyPercent[1], color: .green, label: "Y")
                energyBar(percent: viz.axisEnergyPercent[2], color: .purple, label: "Z")
            }
            Text("Dominant raw axis: \(viz.dominantRawAxis)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func energyBar(percent: Double, color: Color, label: String) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color(.systemGray5))
                Capsule()
                    .fill(color)
                    .frame(height: max(3, 80 * percent / 100))
            }
            .frame(width: 16, height: 80)
            Text("\(label) \(Int(percent))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var readoutGrid: some View {
        VStack(spacing: 0) {
            row("File", viz.name)
            row("Rows", "\(viz.rows)")
            row("Duration", String(format: "%.2f s", viz.duration))
            row("Sample rate", String(format: "%.1f Hz", viz.sampleRateHz))
            row("Initial gravity", vec3(viz.initialGravity))
            row("Gravity angle vs straight", String(format: "%.1f deg", viz.gravityAngleFromStraight))
            row("Path extent (world)", vec3(viz.extents["world"] ?? .zero))
            row("Path extent (raw)", vec3(viz.extents["device"] ?? .zero))
            row("Dominant raw axis", viz.dominantRawAxis)
            row("Raw/world drift ratio", String(format: "%.2fx", viz.rawToWorldDiagRatio))
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)
        }
    }

    private var planeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gesture plane")
                .font(.subheadline.weight(.semibold))
            Group {
                rowText("Normal", vec3(viz.planeNormal))
                rowText("Major axis", vec3(viz.planeMajorAxis))
                rowText("Minor axis", vec3(viz.planeMinorAxis))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func rowText(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }

    private func vec3(_ v: SIMD3<Double>) -> String {
        String(format: "[%.2f, %.2f, %.2f]", v.x, v.y, v.z)
    }
}
