import Foundation

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

struct TrainRecordingAcceptedPayload: Codable {
    let type: TrainPayloadType
    let letter: String
    let nextIndex: Int
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
