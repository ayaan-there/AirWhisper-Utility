import Foundation

/// Centralized app configuration.
///
/// Author: Ayaan
/// Created: 2026-08-31
struct AppConfig {

    /// Admin token for server authentication.
    /// In production, store securely in Keychain.
    static let adminToken = "change-me-in-production"

    /// Server base URL.
    static let serverBaseURL = "https://api.airwhisper.in"

    /// Cloudflare Access service-token credentials.
    /// Values are supplied through the local, git-ignored xcconfig override.
    static let cloudflareAccessClientId =
        Bundle.main.object(forInfoDictionaryKey: "AirWhisperCloudflareAccessClientId") as? String ?? ""
    static let cloudflareAccessClientSecret =
        Bundle.main.object(forInfoDictionaryKey: "AirWhisperCloudflareAccessClientSecret") as? String ?? ""
}
