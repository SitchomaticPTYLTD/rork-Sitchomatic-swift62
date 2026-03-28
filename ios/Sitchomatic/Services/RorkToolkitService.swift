import Foundation

nonisolated struct RorkToolkitMessage: Codable, Sendable {
    let role: String
    let content: String
}

nonisolated struct RorkToolkitTextRequest: Codable, Sendable {
    let messages: [RorkToolkitMessage]
}

nonisolated struct RorkToolkitTextResponse: Codable, Sendable {
    let text: String?
    let error: String?
}

@MainActor
class RorkToolkitService {
    static let shared = RorkToolkitService()

    private let logger = DebugLogger.shared

    /// Grok (xAI) API base URL.
    private let grokBaseURL = "https://api.x.ai"

    /// The Grok model to use for chat completions.
    private let grokModel = "grok-3-mini-fast"

    func generateText(systemPrompt: String, userPrompt: String) async -> String? {
        guard let apiKey = GrokKeychain.shared.getAPIKey(), !apiKey.isEmpty else {
            logger.log("GrokAI: no API key configured — call GrokAISetup.configure(apiKey:)", category: .automation, level: .error)
            return nil
        }

        let endpoint = "\(grokBaseURL)/v1/chat/completions"
        guard let url = URL(string: endpoint) else {
            logger.log("GrokAI: invalid URL \(endpoint)", category: .automation, level: .error)
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": grokModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
            "temperature": 0.7,
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            logger.log("GrokAI: failed to serialize request body", category: .automation, level: .error)
            return nil
        }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }

            if httpResponse.statusCode != 200 {
                let responseBody = String(data: data, encoding: .utf8) ?? "no body"
                logger.log("GrokAI: HTTP \(httpResponse.statusCode) — \(responseBody.prefix(200))", category: .automation, level: .warning)
                return nil
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // xAI uses OpenAI-compatible response format
                if let choices = json["choices"] as? [[String: Any]],
                   let first = choices.first,
                   let message = first["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    return content
                }
                // Fallback for alternative response shapes
                if let text = json["text"] as? String { return text }
            }

            return String(data: data, encoding: .utf8)
        } catch {
            logger.log("GrokAI: request failed — \(error.localizedDescription)", category: .automation, level: .warning)
            return nil
        }
    }
}
