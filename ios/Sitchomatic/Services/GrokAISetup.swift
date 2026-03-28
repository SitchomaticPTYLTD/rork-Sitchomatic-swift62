import Foundation

/// Configuration entry point for Grok AI (xAI) integration.
///
/// Usage — call once at app startup or from a settings screen:
/// ```
/// GrokAISetup.configure(apiKey: "<your-xai-api-key>")
/// ```
///
/// The key is stored in the iOS Keychain (encrypted at rest) and never
/// written to source code, UserDefaults, or any unencrypted store.
@MainActor
enum GrokAISetup {

    /// Persists the Grok API key in the Keychain for use by all AI services.
    /// - Parameter apiKey: The xAI API key (starts with `xai-`).
    /// - Returns: `true` when the key was stored successfully.
    @discardableResult
    static func configure(apiKey: String) -> Bool {
        guard !apiKey.isEmpty else {
            DebugLogger.shared.log("GrokAISetup: empty API key rejected", category: .automation, level: .error)
            return false
        }
        let stored = GrokKeychain.shared.setAPIKey(apiKey)
        if stored {
            DebugLogger.shared.log("GrokAISetup: API key configured successfully", category: .automation, level: .success)
        } else {
            DebugLogger.shared.log("GrokAISetup: failed to store API key in Keychain", category: .automation, level: .error)
        }
        return stored
    }

    /// Returns `true` when a Grok API key is available and AI services can function.
    static var isConfigured: Bool {
        GrokKeychain.shared.hasAPIKey
    }

    /// Removes the stored API key from the Keychain.
    static func reset() {
        GrokKeychain.shared.removeAPIKey()
        DebugLogger.shared.log("GrokAISetup: API key removed", category: .automation, level: .info)
    }
}
