import Foundation

struct IMURecording: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let letter: String
    var index: Int
    let duration: TimeInterval
    let createdAt: Date
    let samples: [MotionSample]
    var drawing: DrawingPattern?

    var label: String {
        "\(letter)\(index)"
    }
}
