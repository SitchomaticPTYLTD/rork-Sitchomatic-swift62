import WebKit

extension WKWebView {

    /// Native async wrapper for `evaluateJavaScript(_:)`.
    /// Eliminates legacy completion-handler bridging and JSON stringification.
    @MainActor
    func evaluateJavaScriptAsync(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// Convenience: evaluate JS and return the result as a String.
    @MainActor
    func evaluateJSString(_ script: String) async -> String? {
        try? await evaluateJavaScriptAsync(script) as? String
    }

    /// Convenience: evaluate JS and return the result as a Bool.
    @MainActor
    func evaluateJSBool(_ script: String) async -> Bool {
        (try? await evaluateJavaScriptAsync(script) as? Bool) ?? false
    }
}
