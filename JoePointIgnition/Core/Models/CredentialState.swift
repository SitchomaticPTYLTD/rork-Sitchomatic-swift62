import Foundation

/// Strictly Sendable model representing a single automation target.
struct AutomationTarget: Sendable, Identifiable {
    let id: String
    let email: String
    let platform: TargetPlatform

    init(email: String, platform: TargetPlatform) {
        self.id = UUID().uuidString
        self.email = email
        self.platform = platform
    }
}

/// Represents the result of a single headless login session.
enum SessionOutcome: String, Sendable {
    case success
    case disabled
    case noAccount
    case fingerprinted
    case timeout
    case connectionFailure
    case unsure
}

/// Sendable struct capturing the result of a DOM evaluation after login attempt.
struct LoginEvaluation: Sendable {
    let isSuccess: Bool
    let isDisabled: Bool
    let isFingerprinted: Bool
    let isNoAccount: Bool
    let rawPageContent: String

    var outcome: SessionOutcome {
        if isFingerprinted { return .fingerprinted }
        if isDisabled { return .disabled }
        if isSuccess { return .success }
        if isNoAccount { return .noAccount }
        return .unsure
    }
}

/// Sendable struct for a discovered working login.
struct FoundLogin: Sendable, Identifiable {
    let id: String
    let email: String
    let password: String
    let platform: TargetPlatform
    let timestamp: Date

    init(email: String, password: String, platform: TargetPlatform) {
        self.id = UUID().uuidString
        self.email = email
        self.password = password
        self.platform = platform
        self.timestamp = Date()
    }

    var exportText: String { "\(email):\(password)" }
}
