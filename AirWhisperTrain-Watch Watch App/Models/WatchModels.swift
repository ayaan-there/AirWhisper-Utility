import Foundation

enum WatchMode {
    case train
    case test
}

struct PredictRequest: Codable {
    let features: [Float]
    let metadata: [String: String]?
}

struct PredictResponse: Codable {
    let letter: String
    let confidence: Float
    let top5: [TopPrediction]
    let dpProb: Float
    let model_version: Int
    let preprocessorVersion: String
    let latencyMs: Float
}

struct TopPrediction: Codable {
    let letter: String
    let prob: Float
}

struct AppConfig {
    static let serverBaseURL = "https://api.airwhisper.in"
    static let cloudflareAccessClientId =
        Bundle.main.object(forInfoDictionaryKey: "AirWhisperCloudflareAccessClientId") as? String ?? ""
    static let cloudflareAccessClientSecret =
        Bundle.main.object(forInfoDictionaryKey: "AirWhisperCloudflareAccessClientSecret") as? String ?? ""
}
