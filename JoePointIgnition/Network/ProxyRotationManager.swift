import Foundation
import Observation

/// Handles IP rotation during the "Burn & Rotate" security protocol.
///
/// When the `DualFindEngine` detects a fingerprint/2FA trigger in the DOM,
/// this manager is called to rotate the proxy/VPN IP before allowing the
/// TaskGroup to spawn the next WebView session.
@Observable
@AutomationActor
final class ProxyRotationManager {

    // MARK: - State

    private(set) var isRotating: Bool = false
    private(set) var rotationCount: Int = 0
    private(set) var lastRotationDate: Date?
    private(set) var rotationLog: [RotationEntry] = []

    struct RotationEntry: Sendable, Identifiable {
        let id: String
        let timestamp: Date
        let reason: String
        let previousIP: String
        let newIP: String

        init(reason: String, previousIP: String = "unknown", newIP: String = "rotated") {
            self.id = UUID().uuidString
            self.timestamp = Date()
            self.reason = reason
            self.previousIP = previousIP
            self.newIP = newIP
        }
    }

    // MARK: - Rotation

    /// Rotates the tunnel IP. Called by `DualFindEngine` during Burn & Rotate.
    func rotateTunnelIP(reason: String) async {
        guard !isRotating else { return }
        isRotating = true
        defer { isRotating = false }

        // Signal the TunnelConfigurator to disconnect and reconnect
        await TunnelConfigurator.shared.disconnectAndRotate()

        rotationCount += 1
        lastRotationDate = Date()

        let entry = RotationEntry(reason: reason)
        rotationLog.insert(entry, at: 0)

        // Keep log bounded
        if rotationLog.count > 50 {
            rotationLog = Array(rotationLog.prefix(50))
        }
    }

    /// Resets rotation state.
    func reset() {
        rotationCount = 0
        lastRotationDate = nil
        rotationLog.removeAll()
    }
}
