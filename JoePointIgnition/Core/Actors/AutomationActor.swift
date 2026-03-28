import Foundation

/// Dedicated global actor that isolates all automation TaskGroup orchestration
/// and DOM parsing off the @MainActor, preventing UI thread contention.
@globalActor
actor AutomationActor {
    static let shared = AutomationActor()
}
