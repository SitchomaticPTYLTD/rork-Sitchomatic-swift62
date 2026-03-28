import Foundation

/// Represents the two target login platforms for dual-site automation.
enum TargetPlatform: String, Sendable, Codable, CaseIterable {
    case joe = "JoePoint"
    case ignition = "Ignition"

    var displayName: String { rawValue }

    var baseURL: URL {
        switch self {
        case .joe:
            URL(string: "https://joepoint.com.au")!
        case .ignition:
            URL(string: "https://ignitioncasino.eu")!
        }
    }
}
