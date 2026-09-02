import Foundation
import Combine

@MainActor
final class RecordingStore: ObservableObject {

    static let maxPerLetter = 100

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    @Published private(set) var recordingsByLetter: [String: [IMURecording]] = [:]

    init() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        encoder = enc
        decoder = dec

        loadAll()
    }

    var allLettersSorted: [String] {
        recordingsByLetter.keys.sorted()
    }

    func recordings(for letter: String) -> [IMURecording] {
        recordingsByLetter[letter] ?? []
    }

    func canAdd(letter: String) -> Bool {
        (recordingsByLetter[letter] ?? []).count < Self.maxPerLetter
    }

    func nextIndex(for letter: String) -> Int {
        recordings(for: letter).count + 1
    }

    @discardableResult
    func add(_ recording: IMURecording, letter: String) -> IMURecording {
        var list = recordingsByLetter[letter] ?? []
        guard list.count < Self.maxPerLetter else { return recording }
        var rec = recording
        rec.index = list.count + 1
        list.append(rec)
        list.sort { $0.index < $1.index }
        recordingsByLetter[letter] = list
        save(letter: letter, list: list)
        return rec
    }

    func delete(_ ids: Set<UUID>, letter: String) {
        var list = recordingsByLetter[letter] ?? []
        list.removeAll { ids.contains($0.id) }
        for (offset, index) in list.indices.enumerated() {
            list[index].index = offset + 1
        }
        recordingsByLetter[letter] = list
        save(letter: letter, list: list)
    }

    func url(for letter: String) -> URL {
        let dir = documentsDirectory.appendingPathComponent("recordings", isDirectory: true)
        return dir.appendingPathComponent("\(letter).json")
    }

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func loadAll() {
        let dir = documentsDirectory.appendingPathComponent("recordings", isDirectory: true)
        guard let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            let letter = file.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: file),
                  let list = try? decoder.decode([IMURecording].self, from: data) else { continue }
            recordingsByLetter[letter] = list.sorted { $0.index < $1.index }
        }
    }

    private func save(letter: String, list: [IMURecording]) {
        let dir = documentsDirectory.appendingPathComponent("recordings", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            let data = try encoder.encode(list)
            try data.write(to: url(for: letter))
        } catch {
            print("RecordingStore save error: \(error)")
        }
    }
}
