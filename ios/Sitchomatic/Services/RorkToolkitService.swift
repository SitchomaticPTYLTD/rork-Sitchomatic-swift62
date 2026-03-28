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

    func generateText(systemPrompt: String, userPrompt: String) async -> String? {
        return nil
    }
}
