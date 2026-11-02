#if canImport(NetworkExtension)
import Foundation
import NetworkExtension
import VLESSKit

/// App-side control of your packet-tunnel extension: saves one VPN configuration (iOS asks the user once),
/// then starts and stops the tunnel with a share link.
///
/// ```swift
/// let vpn = VLESSTunnelManager(extensionBundleId: "com.example.app.tunnel", name: "My VPN")
/// try await vpn.connect("vless://…")
/// ```
@MainActor
public final class VLESSTunnelManager: ObservableObject {
    public let extensionBundleId: String
    public let name: String

    @Published public private(set) var status: NEVPNStatus = .invalid

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?

    public init(extensionBundleId: String, name: String) {
        self.extensionBundleId = extensionBundleId
        self.name = name
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { [weak self] note in
            guard let connection = note.object as? NEVPNConnection else { return }
            Task { @MainActor in self?.status = connection.status }
        }
        Task { await load() }
    }

    /// Loads the configuration saved earlier, if any.
    public func load() async {
        let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        manager = managers.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == extensionBundleId }
        if let manager { status = manager.connection.status }
    }

    /// Saves the configuration and starts the tunnel; restarts it if it's already running.
    public func connect(_ link: String) async throws {
        guard let parsed = ShareLink.parse(link) else { throw VLESSKitError.unsupportedLink }
        let manager = manager ?? NETunnelProviderManager()
        let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = extensionBundleId
        proto.serverAddress = parsed.host
        // Kept so the system can restart the tunnel by itself (on demand, after a reboot).
        proto.providerConfiguration = [VLESSTunnelManager.linkKey: link]
        manager.protocolConfiguration = proto
        manager.localizedDescription = name
        manager.isEnabled = true
        try await manager.saveToPreferences()
        // Saving invalidates the in-memory copy; reload before starting.
        try await manager.loadFromPreferences()
        self.manager = manager

        if manager.connection.status != .disconnected && manager.connection.status != .invalid {
            manager.connection.stopVPNTunnel()
            await waitUntilDisconnected(manager.connection)
        }
        try manager.connection.startVPNTunnel(options: [VLESSTunnelManager.linkKey: link as NSString])
    }

    /// Stops the tunnel. `removeConfiguration` also deletes it from Settings → VPN (e.g. on sign-out).
    public func disconnect(removeConfiguration: Bool = false) async {
        guard let manager else { return }
        manager.connection.stopVPNTunnel()
        if removeConfiguration {
            await waitUntilDisconnected(manager.connection)
            try? await manager.removeFromPreferences()
            self.manager = nil
            status = .invalid
        }
    }

    /// Why the last connection attempt ended, as reported by the extension.
    public func lastError() async -> Error? {
        guard let connection = manager?.connection else { return nil }
        return await withCheckedContinuation { continuation in
            connection.fetchLastDisconnectError { continuation.resume(returning: $0) }
        }
    }

    /// Same key `XrayPacketTunnelProvider` reads.
    public nonisolated static let linkKey = "link"

    private func waitUntilDisconnected(_ connection: NEVPNConnection) async {
        for _ in 0..<50 where connection.status != .disconnected && connection.status != .invalid {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
#endif
