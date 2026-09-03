import Foundation

/// Centralized API service for communicating with the AirWhisper server.
/// Handles all HTTP requests: sample upload, prediction, config, training status.
///
/// Author: Ayaan
/// Created: 2026-08-31
final class APIService {

    static let baseURL = AppConfig.serverBaseURL
    static let shared = APIService()

    private let session = URLSession.shared
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Adds the Cloudflare Access service-token headers to an app request.
    /// Empty values are intentionally omitted so development builds remain usable
    /// before the protected Access policy is enabled.
    private func addCloudflareAccessHeaders(to request: inout URLRequest) {
        if !AppConfig.cloudflareAccessClientId.isEmpty {
            request.setValue(AppConfig.cloudflareAccessClientId, forHTTPHeaderField: "CF-Access-Client-Id")
        }
        if !AppConfig.cloudflareAccessClientSecret.isEmpty {
            request.setValue(AppConfig.cloudflareAccessClientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        }
    }

    // MARK: - Error Types

    enum APIError: LocalizedError {
        case invalidURL
        case invalidResponse
        case serverError(Int, String)
        case decodingError(Error)
        case encodingError(Error)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid server URL"
            case .invalidResponse: return "Invalid server response"
            case .serverError(let code, let msg): return "Server error \(code): \(msg)"
            case .decodingError(let e): return "Decoding error: \(e.localizedDescription)"
            case .encodingError(let e): return "Encoding error: \(e.localizedDescription)"
            case .networkError(let e): return "Network error: \(e.localizedDescription)"
            }
        }
    }

    // MARK: - Sample Upload (Labeled)

    /// Upload a labeled sample to the server.
    /// - Parameters:
    ///   - letter: Target letter (A-Z)
    ///   - zipData: Raw SensorLogger ZIP data
    ///   - posture: Optional posture hint (straight, elbow90, supinated, etc.)
    ///   - modelVersion: Model version used during recording
    ///   - appVersion: App version string
    /// - Returns: Server response with updated counts
    func uploadSample(
        letter: String,
        zipData: Data,
        posture: String = "unknown",
        modelVersion: Int,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    ) async throws -> SampleUploadResponse {
        let url = URL(string: "\(Self.baseURL)/samples")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addCloudflareAccessHeaders(to: &request)

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let letterData = letter.data(using: .utf8)!
        let modelVersionData = String(modelVersion).data(using: .utf8)!
        let appVersionData = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let appVersionDataEncoded = appVersionData.data(using: .utf8)!

        // Build multipart body
        func appendField(_ name: String, _ value: Data) {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append(value)
            body.append("\r\n")
        }

        appendField("letter", letterData)
        appendField("model_version", modelVersionData)
        appendField("app_version", appVersionDataEncoded)
        appendField("posture", posture.data(using: .utf8)!)
        appendField("consent", "true".data(using: .utf8)!)

        // File part
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"zip_file\"; filename=\"sample.zip\"\r\n")
        body.append("Content-Type: application/zip\r\n\r\n")
        body.append(zipData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(httpResponse.statusCode, msg)
        }

        return try decoder.decode(SampleUploadResponse.self, from: data)
    }

    // MARK: - Prediction (Inference)

    /// Send a raw ZIP to the server for prediction.
    /// - Parameter zipData: Raw SensorLogger ZIP data
    /// - Returns: Predicted letter, top-5 probabilities, D/P probability, model version
    func predict(zipData: Data) async throws -> PredictResponse {
        let url = URL(string: "\(Self.baseURL)/predict")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addCloudflareAccessHeaders(to: &request)

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"zip_file\"; filename=\"sample.zip\"\r\n")
        body.append("Content-Type: application/zip\r\n\r\n")
        body.append(zipData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(httpResponse.statusCode, msg)
        }

        return try decoder.decode(PredictResponse.self, from: data)
    }

    // MARK: - Server Counts

    /// Fetch per-class sample counts from the server.
    func fetchServerCounts() async throws -> ServerCountsResponse {
        let url = URL(string: "\(Self.baseURL)/samples/counts")!
        var request = URLRequest(url: url)
        addCloudflareAccessHeaders(to: &request)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw APIError.invalidResponse
        }
        return try decoder.decode(ServerCountsResponse.self, from: data)
    }

    // MARK: - Training Status

    /// Fetch current training status (epoch, loss, val_acc, ETA).
    func fetchTrainingStatus() async throws -> TrainStatusResponse {
        let url = URL(string: "\(Self.baseURL)/train/status")!
        var request = URLRequest(url: url)
        addCloudflareAccessHeaders(to: &request)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw APIError.invalidResponse
        }
        return try decoder.decode(TrainStatusResponse.self, from: data)
    }

    // MARK: - Config

    /// Fetch current training configuration.
    func fetchConfig() async throws -> TrainConfig {
        let url = URL(string: "\(Self.baseURL)/config")!
        var request = URLRequest(url: url)
        addCloudflareAccessHeaders(to: &request)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw APIError.invalidResponse
        }
        return try decoder.decode(TrainConfig.self, from: data)
    }

    /// Update training configuration (admin only).
    func updateConfig(_ config: TrainConfig, adminToken: String) async throws {
        var request = URLRequest(url: URL(string: "\(Self.baseURL)/config")!)
        request.httpMethod = "PUT"
        addCloudflareAccessHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(adminToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(ConfigUpdate(config: config))

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw APIError.invalidResponse
        }
    }

    // MARK: - Manual Train Trigger

    func triggerTraining(adminToken: String) async throws {
        var request = URLRequest(url: URL(string: "\(Self.baseURL)/train/trigger")!)
        request.httpMethod = "POST"
        addCloudflareAccessHeaders(to: &request)
        request.setValue("Bearer \(adminToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw APIError.invalidResponse
        }
    }

    // MARK: - Trigger Check

    func checkTriggerConditions() async throws -> TriggerCheckResponse {
        let url = URL(string: "\(Self.baseURL)/trigger/check")!
        var request = URLRequest(url: url)
        addCloudflareAccessHeaders(to: &request)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw APIError.invalidResponse
        }
        return try decoder.decode(TriggerCheckResponse.self, from: data)
    }

    // MARK: - Preprocessed Sample Upload (New)

    /// Upload preprocessed features directly (bypasses server-side preprocessing).
    /// - Parameters:
    ///   - letter: Target letter (A-Z)
    ///   - features: 15-feature array [384][15] as flat Float32 array
    ///   - metadata: Optional metadata
    /// - Returns: Server response
    func uploadPreprocessedSample(
        letter: String,
        features: [Float],
        metadata: PreprocessedSampleMetadata
    ) async throws -> SampleUploadResponse {
        let url = URL(string: "\(Self.baseURL)/samples/preprocessed")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addCloudflareAccessHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = PreprocessedSamplePayload(
            letter: letter,
            features: features,
            metadata: metadata
        )
        request.httpBody = try encoder.encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(httpResponse.statusCode, msg)
        }

        return try decoder.decode(SampleUploadResponse.self, from: data)
    }

    // MARK: - Delete Sample

    /// Delete a specific sample by ID for a given letter.
    /// - Parameters:
    ///   - letter: Target letter (A-Z)
    ///   - sampleId: Sample ID to delete
    ///   - adminToken: Admin token for authorization
    /// - Returns: Server response with updated counts
    func deleteSample(
        letter: String,
        sampleId: String,
        adminToken: String
    ) async throws -> SampleUploadResponse {
        let url = URL(string: "\(Self.baseURL)/samples/\(letter.uppercased())/\(sampleId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addCloudflareAccessHeaders(to: &request)
        request.setValue("Bearer \(adminToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(httpResponse.statusCode, msg)
        }

        return try decoder.decode(SampleUploadResponse.self, from: data)
    }
}

// MARK: - Response Models

struct SampleUploadResponse: Codable {
    let accepted: Bool
    let serverCount: Int
    let globalCount: Int
    let message: String
}

struct PredictResponse: Codable {
    let letter: String
    let top5: [TopPrediction]
    let dpProb: Float
    let modelVersion: Int
    let preprocessorVersion: String
    let latencyMs: Float
}

struct TopPrediction: Codable {
    let letter: String
    let prob: Float
}

struct ServerCountsResponse: Codable {
    let perClass: [String: Int]
    let total: Int
    let capPerClass: Int
    let deficit: [String: Int]
}

struct TrainStatusResponse: Codable {
    let state: String
    let epoch: Int
    let totalEpochs: Int
    let loss: Float?
    let valAcc: Float?
    let valLoss: Float?
    let etaSec: Int
    let startedAt: String?
    let finishedAt: String?
    let error: String?
}

struct TrainConfig: Codable {
    let trigger: TriggerConfig
    let training: TrainingConfig
    let augment: AugmentConfig
    let dpHead: DPHeadConfig
    let oversample: OversampleConfig
    let dataset: DatasetConfig
    let server: ServerConfig
}

struct TriggerConfig: Codable {
    let minPerClass: Int
    let balanceRatio: Float
    let globalMin: Int
    let maxIntervalHours: Int
    let allowForceOnInterval: Bool
    let minNewPerClass: Int
}

struct TrainingConfig: Codable {
    let lstmUnits: Int
    let gruUnits: Int
    let dropout: Float
    let lr: Float
    let batch: Int
    let maxEpochs: Int
    let patience: Int
    let minDelta: Float
    let useClassWeights: Bool
    let focusClassWeight: Float
}

struct AugmentConfig: Codable {
    let enabled: Bool
    let copies: Int
    let baseProb: Float
    let focusProb: Float
    let noiseStd: Float
    let scaleJitter: Float
    let timeShift: Int
    let timeMaskMax: Int
    let timeMaskFill: Float
    let rotateProb: Float
    let rotateMaxDeg: Float
    let warpMin: Float
    let warpMax: Float
    let warpMaxShiftFrac: Float
    let focusClasses: [String]
    let focusClassWeight: Float
}

struct DPHeadConfig: Codable {
    let enabled: Bool
    let lossWeight: Float
    let gate: String
}

struct OversampleConfig: Codable {
    let lh90Repeat: Int
    let sup80Repeat: Int
}

struct DatasetConfig: Codable {
    let hardCapPerClass: Int
    let enforceOnServer: Bool
    let rejectExcess: Bool
}

struct ServerConfig: Codable {
    let modelPath: String
    let preprocessorModule: String
    let samplesRoot: String
    let maxZipMb: Int
    let adminToken: String
    let features: Int
    let seqLen: Int
    let classes: Int
}

struct ConfigUpdate: Codable {
    let config: TrainConfig
}

struct TriggerCheckResponse: Codable {
    let shouldTrigger: Bool
    let reason: String
    let counts: [String: Int]
    let total: Int
    let thresholds: TriggerConfig
}

// MARK: - Preprocessed Sample Types

struct PreprocessedSampleMetadata: Codable {
    let posture: String
    let modelVersion: Int
    let appVersion: String
    let timestamp: String
    let deviceId: String
}

struct PreprocessedSamplePayload: Codable {
    let letter: String
    let features: [Float]
    let metadata: PreprocessedSampleMetadata
}

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
