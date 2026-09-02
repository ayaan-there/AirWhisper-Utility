import SwiftUI
import UniformTypeIdentifiers

/// Let the user pick a raw IMU CSV from Files and visualise it exactly like a
/// recording dropped onto the reference `airwhisper_imu_visualizer.html` web
/// tool.
struct CSVImportView: View {

    let onImported: (IMURecording) -> Void

    @State private var showingPicker = false
    @State private var recording: IMURecording?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let supportedTypes: [UTType] = [.commaSeparatedText, .plainText, .data]

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.brandBlue)

            Text("Visualise an IMU CSV")
                .font(.title3.weight(.bold))

            Text("Pick a raw IMU sample CSV (the format used by the sample set — time, seconds_elapsed, rotationRateX/Y/Z, gravityX/Y/Z, accelerationX/Y/Z, quaternionW/X/Y/Z).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showingPicker = true
            } label: {
                Label(isLoading ? "Parsing…" : "Choose CSV File", systemImage: "folder")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.brandBlue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)

            if let recording {
                Button {
                    onImported(recording)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.rectangle.fill")
                            .foregroundStyle(AppTheme.brandBlue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recording.label)
                                .font(.subheadline.weight(.semibold))
                            Text("\(recording.samples.count) samples · \(String(format: "%.1f", recording.duration))s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Import CSV")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: supportedTypes, allowsMultipleSelection: false) { result in
            handleResult(result)
        }
        .alert("Could not load CSV", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func handleResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let securityScoped = url.startAccessingSecurityScopedResource()
            defer {
                if securityScoped { url.stopAccessingSecurityScopedResource() }
            }
            isLoading = true
            do {
                let data = try Data(contentsOf: url)
                let text = String(decoding: data, as: UTF8.self)
                let rec = try IMUCSVImporter.makeRecording(text, fileName: url.lastPathComponent)
                recording = rec
                isLoading = false
            } catch {
                recording = nil
                errorMessage = (error as? IMUCSVImporter.ParseError)?.message ?? error.localizedDescription
                isLoading = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        CSVImportView(onImported: { _ in })
    }
}
