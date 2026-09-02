import Foundation
import Observation

@Observable
@MainActor
final class InferenceService {
    private let baseURL = AppConfig.serverBaseURL
    private let session = URLSession.shared
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func predict(features: [Float]) async throws -> PredictResponse {
        let url = URL(string: "\(baseURL)/predict")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = PredictRequest(features: features, metadata: nil)
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw InferenceError.serverError
        }

        return try decoder.decode(PredictResponse.self, from: data)
    }
}

enum InferenceError: LocalizedError {
    case serverError
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .serverError: return "Server error during inference"
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        }
    }
}