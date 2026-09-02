import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {

    static let shared = AppModel()

    let connectivity: TrainPhoneConnectivityManager
    let store: RecordingStore

    @Published var selectedLetter: String?
    @Published var justReceivedLetter: String?

    private(set) var drawingByLetter: [String: DrawingPattern] = [:]

    private var cancellables = Set<AnyCancellable>()

    private init() {
        connectivity = TrainPhoneConnectivityManager.shared
        store = RecordingStore()
        connectivity.onReceivedRecording = { [weak self] recording in
            Task { @MainActor in
                self?.handleReceivedRecording(recording)
            }
        }
        connectivity.onStateRequested = { [weak self] in
            let letter = self?.selectedLetter
            let count = letter.map { self?.store.recordings(for: $0).count ?? 0 } ?? 0
            return TrainStateResponsePayload(type: .stateResponse, letter: letter, count: count)
        }
    }

    private func handleReceivedRecording(_ recording: IMURecording) {
        let letter = recording.letter
        var rec = recording
        if let drawing = drawingByLetter[letter] {
            rec.drawing = drawing
        }
        store.add(rec, letter: letter)
        selectedLetter = letter
        justReceivedLetter = letter
        let next = store.nextIndex(for: letter)
        connectivity.sendAccepted(letter: letter, nextIndex: next)
    }

    func submitLetter(_ letter: String, drawing: DrawingPattern? = nil) {
        if let drawing {
            drawingByLetter[letter] = drawing
        }
        selectedLetter = letter
        let count = store.recordings(for: letter).count
        guard count < RecordingStore.maxPerLetter else { return }
        let next = store.nextIndex(for: letter)
        connectivity.selectLetter(letter, expectedIndex: next)
    }
}
