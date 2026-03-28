import Foundation
@preconcurrency import NetworkExtension
import Observation

/// Interfaces with `NEPacketTunnelProvider` to manage VPN tunnel connections.
///
/// Provides a clean async API for connecting, disconnecting, and rotating
/// tunnel configurations. Used by `ProxyRotationManager` during the
/// "Burn & Rotate" protocol.
@Observable
@MainActor
final class TunnelConfigurator {

    static let shared = TunnelConfigurator()

    // MARK: - State

    enum TunnelStatus: String, Sendable {
        case disconnected
        case connecting
        case connected
        case disconnecting
        case error
    }

    private(set) var status: TunnelStatus = .disconnected
    private(set) var currentConfigName: String?
    private(set) var lastError: String?

    private var tunnelManager: NETunnelProviderManager?

    // MARK: - Lifecycle

    /// Loads the existing tunnel configuration from system preferences.
    func loadConfiguration() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            tunnelManager = managers.first
            if tunnelManager != nil {
                status = .disconnected
            }
        } catch {
            lastError = error.localizedDescription
            status = .error
        }
    }

    /// Connects the tunnel with the current configuration.
    func connect() async {
        guard let manager = tunnelManager else {
            lastError = "No tunnel configuration loaded"
            status = .error
            return
        }

        status = .connecting
        do {
            try manager.connection.startVPNTunnel()
            status = .connected
        } catch {
            lastError = error.localizedDescription
            status = .error
        }
    }

    /// Disconnects the active tunnel.
    func disconnect() {
        tunnelManager?.connection.stopVPNTunnel()
        status = .disconnected
        currentConfigName = nil
    }

    /// Disconnects and rotates to a new IP by re-establishing the tunnel.
    /// This is the core action of the "Burn & Rotate" protocol.
    func disconnectAndRotate() async {
        disconnect()

        // Brief cooldown before reconnecting to ensure IP release
        try? await Task.sleep(for: .milliseconds(500))

        await connect()
    }

    /// Saves a new WireGuard tunnel configuration.
    func saveTunnelConfiguration(
        serverAddress: String,
        port: Int,
        privateKey: String,
        publicKey: String,
        presharedKey: String? = nil
    ) async {
        let manager = tunnelManager ?? NETunnelProviderManager()

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = "com.joepointignition.tunnel"
        proto.serverAddress = serverAddress
        proto.providerConfiguration = [
            "port": port,
            "privateKey": privateKey,
            "publicKey": publicKey,
            "presharedKey": presharedKey ?? ""
        ]

        manager.protocolConfiguration = proto
        manager.localizedDescription = "JoePointIgnition VPN"
        manager.isEnabled = true

        do {
            try await manager.saveToPreferences()
            tunnelManager = manager
            currentConfigName = serverAddress
            status = .disconnected
        } catch {
            lastError = error.localizedDescription
            status = .error
        }
    }
}
