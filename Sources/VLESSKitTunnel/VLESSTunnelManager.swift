#if canImport(NetworkExtension)
import Foundation
import NetworkExtension
import VLESSKit

/// Installs the VPN configuration and starts or stops the tunnel from the app.
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

    public func load() async {
        let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        manager = managers.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == extensionBundleId }
        if let manager { status = manager.connection.status }
    }

    public func connect(_ link: String) async throws {
        guard let parsed = ProxyLink.parse(link) else { throw VLESSKitError.unsupportedLink }
        let manager = manager ?? NETunnelProviderManager()
        let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = extensionBundleId
        proto.serverAddress = parsed.host
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

    public func lastError() async -> Error? {
        guard let connection = manager?.connection else { return nil }
        return await withCheckedContinuation { continuation in
            connection.fetchLastDisconnectError { continuation.resume(returning: $0) }
        }
    }

    /// Bytes through the proxy since the tunnel started; nil when it isn't running.
    public func traffic() async -> XrayTraffic? {
        guard let session = manager?.connection as? NETunnelProviderSession, session.status == .connected else { return nil }
        return await withCheckedContinuation { continuation in
            do {
                try session.sendProviderMessage(Self.trafficMessage) { data in
                    continuation.resume(returning: data.flatMap { try? JSONDecoder().decode(XrayTraffic.self, from: $0) })
                }
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    public nonisolated static let linkKey = "link"
    nonisolated static let trafficMessage = Data("traffic".utf8)

    private func waitUntilDisconnected(_ connection: NEVPNConnection) async {
        for _ in 0..<50 where connection.status != .disconnected && connection.status != .invalid {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
#endif
