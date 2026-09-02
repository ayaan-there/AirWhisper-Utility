import Foundation

struct IMURecording: Codable, Identifiable, Equatable {
    let id: UUID
    let letter: String
    let index: Int
    let duration: TimeInterval
    let createdAt: Date
    let samples: [MotionSample]

    init(id: UUID = UUID(), letter: String, index: Int, duration: TimeInterval, createdAt: Date = Date(), samples: [MotionSample]) {
        self.id = id
        self.letter = letter
        self.index = index
        self.duration = duration
        self.createdAt = createdAt
        self.samples = samples
    }
}

enum TrainPayloadType: String, Codable, Equatable {
    case letterSelected
    case recordingPayload
    case recordingAccepted
    case requestState
    case stateResponse
}

struct TrainLetterSelectedPayload: Codable {
    let type: TrainPayloadType
    let letter: String
    let expectedIndex: Int
}

struct TrainRecordingPayload: Codable {
    let type: TrainPayloadType
    let recording: IMURecording
}

struct TrainStateResponsePayload: Codable {
    let type: TrainPayloadType
    let letter: String?
    let count: Int
}

struct TrainRecordingAcceptedPayload: Codable {
    let type: TrainPayloadType
    let letter: String
    let nextIndex: Int
}
