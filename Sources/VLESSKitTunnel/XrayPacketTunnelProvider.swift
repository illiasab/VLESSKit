#if os(iOS) && canImport(Libv2ray)
import NetworkExtension
import os

/// Runs Xray-core in-process on the utun fd. Use it as your extension's principal class:
/// `final class PacketTunnelProvider: XrayPacketTunnelProvider {}`
open class XrayPacketTunnelProvider: NEPacketTunnelProvider {
    public static let linkKey = "link"
    /// App message asking for ``XrayTraffic`` as JSON; see `VLESSTunnelManager.traffic()`.
    public static let trafficMessage = Data("traffic".utf8)

    public let log = Logger(subsystem: "VLESSKit", category: "tunnel")
    private lazy var engine = XrayEngine { [weak self] code, message in self?.coreDidEmit(code: code, message: message) }

    open var configOptions: XrayConfig.Options { .default }

    /// Override to supply your own config; it must keep the `tun` inbound.
    open func makeConfig(for link: ProxyLink) throws -> String {
        try XrayConfig.jsonString(link, options: configOptions)
    }

    override open func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let saved = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        guard let raw = (options?[Self.linkKey] as? String) ?? (saved?[Self.linkKey] as? String),
              let link = ProxyLink.parse(raw) else {
            completionHandler(VLESSKitError.unsupportedLink)
            return
        }

        setTunnelNetworkSettings(makeNetworkSettings()) { [weak self] error in
            guard let self else { return }
            if let error {
                completionHandler(error)
                return
            }
            do {
                guard let fd = self.tunnelFileDescriptor else { throw VLESSKitError.noTunnelDescriptor }
                try self.engine.start(config: try self.makeConfig(for: link), tunFd: fd)
                completionHandler(nil)
            } catch {
                self.log.error("connect failed: \(error.localizedDescription, privacy: .public)")
                completionHandler(error)
            }
        }
    }

    override open func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        do { try engine.stop() } catch { log.warning("stop: \(error.localizedDescription, privacy: .public)") }
        completionHandler()
    }

    override open func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard messageData == Self.trafficMessage else {
            completionHandler?(nil)
            return
        }
        completionHandler?(try? JSONEncoder().encode(engine.refreshTraffic()))
    }

    open func coreDidEmit(code: Int, message: String) {
        log.info("xray[\(code)] \(message, privacy: .public)")
    }

    open func makeNetworkSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.10.14.2")
        settings.mtu = NSNumber(value: configOptions.mtu)

        let ipv4 = NEIPv4Settings(addresses: ["10.10.14.1"], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        let ipv6 = NEIPv6Settings(addresses: ["fc00::10:10:14:1"], networkPrefixLengths: [126])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6

        let dns = NEDNSSettings(servers: XrayConfig.tunnelDNS)
        dns.matchDomains = [""]
        settings.dnsSettings = dns
        return settings
    }

    /// NetworkExtension doesn't expose the utun fd, so find the socket whose name starts with "utun".
    private var tunnelFileDescriptor: Int32? {
        var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        let prefix = Array("utun".utf8CString.dropLast())
        for fd: Int32 in 0...1024 {
            var length = socklen_t(name.count)
            // SYSPROTO_CONTROL = 2, UTUN_OPT_IFNAME = 2
            if getsockopt(fd, 2, 2, &name, &length) == 0, name.starts(with: prefix) { return fd }
        }
        return nil
    }
}
#endif
