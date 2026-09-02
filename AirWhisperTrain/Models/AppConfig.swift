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
    static let serverBaseURL = "http://127.0.0.1:8001"
}