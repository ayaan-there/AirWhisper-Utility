import SwiftUI

struct RecordingsListView: View {

    let letter: String
    @ObservedObject var model: AppModel

    @State private var selection = Set<UUID>()
    @State private var isSelecting = false
    @State private var showSubmitConfirmation = false
    @State private var submitted = false
    @State private var showSendConfirmation = false
    @State private var showLimitAlert = false
    @State private var limitAlertMessage = ""
    @State private var limitAlertAction: (() -> Void)?
    @State private var isSending = false
    @State private var sendProgress: Double = 0

    private var recordings: [IMURecording] {
        model.store.recordings(for: letter)
    }

    private var localCount: Int {
        recordings.count
    }

    private var canRecordMore: Bool {
        localCount < RecordingStore.maxPerLetter
    }

    private var hasReachedMinimum: Bool {
        localCount >= 25
    }

    private var hasReachedMaximum: Bool {
        localCount >= RecordingStore.maxPerLetter
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if recordings.isEmpty {
                emptyState
            } else {
                list
            }
            sendBar
        }
        .navigationTitle("\(letter) Recordings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !recordings.isEmpty {
                    Button(isSelecting ? "Cancel" : "Select") {
                        isSelecting.toggle()
                        selection.removeAll()
                    }
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                if !recordings.isEmpty {
                    NavigationLink(value: "overview") {
                        Text("Overview")
                    }
                }
            }
        }
        .onAppear {
            model.submitLetter(letter)
        }
        .navigationDestination(for: String.self) { dest in
            if dest == "overview" {
                VisualizationOverviewScreen(model: model, letter: letter)
            }
        }
        .navigationDestination(for: IMURecording.self) { rec in
            VisualizationScreen(recording: rec)
        }
        .alert("Limit Reached", isPresented: $showLimitAlert) {
            Button("Yes, Add More", role: .none) {
                limitAlertAction?()
            }
            Button("No, Discard", role: .destructive) {
                // Discard the last sample
                if let lastRecording = recordings.last {
                    model.store.delete([lastRecording.id], letter: letter)
                }
            }
        } message: {
            Text(limitAlertMessage)
        }
        .confirmationDialog("Send \(recordings.count) samples for \(letter)?", isPresented: $showSendConfirmation, titleVisibility: .visible) {
            Button("Send Now", role: .none) {
                Task { await sendSamplesToServer() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will upload \(recordings.count) samples for \(letter) to the server for retraining. You can continue recording more samples after sending (up to 100 total).")
        }
        .confirmationDialog("Submit \(letter) dataset?", isPresented: $showSubmitConfirmation, titleVisibility: .visible) {
            Button("Submit \(recordings.count) samples", role: .destructive) {
                submitted = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This marks \(letter) as complete.")
        }
        .overlay {
            if isSending {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView(value: sendProgress, total: 1.0)
                        .frame(width: 200)
                    Text("Sending \(Int(sendProgress * 100))%")
                        .foregroundStyle(.white)
                }
                .padding(24)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var recordingCount: Int {
        recordings.count
    }

    private var list: some View {
        List {
            ForEach(recordings) { rec in
                row(rec)
            }
            .onDelete { indexSet in
                let ids = Set(indexSet.map { recordings[$0].id })
                // Delete from server first
                Task {
                    do {
                        for id in ids {
                            _ = try await APIService.shared.deleteSample(
                                letter: letter,
                                sampleId: id.uuidString,
                                adminToken: AppConfig.adminToken
                            )
                        }
                    } catch {
                        print("[RecordingsListView] Failed to delete from server: \(error)")
                    }
                }
                // Then delete locally
                model.store.delete(ids, letter: letter)
            }
        }
        .listStyle(.plain)
    }

    private func row(_ rec: IMURecording) -> some View {
        Group {
            if isSelecting {
                Button {
                    toggleSelection(rec.id)
                } label: {
                    HStack {
                        Image(systemName: selection.contains(rec.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(AppTheme.brandBlue)
                        rowContent(rec)
                    }
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: rec) {
                    rowContent(rec)
                }
            }
        }
    }

    private func rowContent(_ rec: IMURecording) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(rec.label)
                    .font(.headline)
                Text(rec.createdAt.formatted(.dateTime.month().day().hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(durationText(rec.duration))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func toggleSelection(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) }
        else { selection.insert(id) }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No recordings yet")
                .font(.headline)
            Text("Pick a letter, draw it, then record samples in the air on your Apple Watch. They will appear here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(letter) — \(localCount)/100")
                        .font(.title3.weight(.bold))
                    Text(isSelecting ? "\(selection.count) selected" : "Local: \(localCount)/100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelecting && !recordings.isEmpty {
                    Button(role: .destructive) {
                        model.store.delete(selection, letter: letter)
                        selection.removeAll()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.subheadline)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            // Progress bar
            ProgressView(value: Double(localCount), total: Double(RecordingStore.maxPerLetter))
                .tint(AppTheme.brandBlue)
                .padding(.horizontal)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var sendBar: some View {
        VStack(spacing: 12) {
            // Progress indicator
            HStack {
                Text("\(localCount)/100 samples")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(localCount >= 100 ? "100/100 - Full" : (localCount >= 25 ? "Ready to send" : "Need \(25 - localCount) more to send"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(localCount >= 100 ? .red : (localCount >= 25 ? .green : .orange))
            }
            .padding(.horizontal)

            // Action buttons
            HStack(spacing: 12) {
                // Send button (enabled at 25+)
                Button {
                    if localCount >= 25 {
                        showSendConfirmation = true
                    } else {
                        // Show minimum not reached
                    }
                } label: {
                    HStack {
                        if isSending {
                            ProgressView()
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(localCount >= 25 ? "Send to Server" : "Need 25 to Send")
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(localCount >= 25 && !isSending ? AppTheme.brandBlue : Color.gray.opacity(0.4))
                    .foregroundStyle(localCount >= 25 ? .white : .white.opacity(0.6))
                    .clipShape(Capsule())
                }
                .disabled(localCount < 25 || isSending)

                // Add more button (enabled if not at max)
                Button {
                    if localCount >= RecordingStore.maxPerLetter {
                        showLimitAlert(
                            message: "100/100 reached for \(letter). No more samples can be taken. Please give samples for other letters.",
                            action: {}
                        )
                    } else if localCount >= 25 {
                        showLimitAlert(
                            message: "Current count for \(letter) is \(localCount)/100. Do you still want to add more samples?",
                            action: {}
                        )
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(localCount >= RecordingStore.maxPerLetter ? .gray : AppTheme.brandBlue)
                }
                .disabled(localCount >= RecordingStore.maxPerLetter)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    private func showLimitAlert(message: String, action: @escaping () -> Void) {
        limitAlertMessage = message
        limitAlertAction = action
        showLimitAlert = true
    }

    private func sendSamplesToServer() async {
        isSending = true
        sendProgress = 0.0
        defer { isSending = false }

        do {
            _ = recordings.count
            for (index, rec) in recordings.enumerated() {
                // Extract 15-feature vectors from recording samples
                let features = MotionSample.extractFeatures(from: rec.samples)
                
                let metadata = PreprocessedSampleMetadata(
                    posture: "auto",
                    modelVersion: 1, // Will be updated from server config
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                    timestamp: ISO8601DateFormatter().string(from: Date()),
                    deviceId: UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
                )
                
                // Use APIService for consistent error handling
                let response = try await APIService.shared.uploadPreprocessedSample(
                    letter: letter,
                    features: features,
                    metadata: metadata
                )
                
                // Update progress
                sendProgress = Double(index + 1) / Double(recordings.count)
                
                // Log server response
                if !response.accepted {
                    print("[RecordingsListView] Server rejected sample \(index + 1): \(response.message)")
                }
            }
            
            // After all sent
            await MainActor.run {
                showSendConfirmation = false
            }
        } catch {
            print("[RecordingsListView] Failed to send samples: \(error)")
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        String(format: "%.1fs", duration)
    }
}