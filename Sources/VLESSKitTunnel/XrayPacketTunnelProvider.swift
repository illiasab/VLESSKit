#if os(iOS) && canImport(Libv2ray)
import Libv2ray
import NetworkExtension
import os
@_exported import VLESSKit

/// A packet tunnel that runs Xray-core in-process. Xray reads packets straight from the utun fd that
/// NetworkExtension created (its `tun` inbound), so no tun2socks bridge is needed.
///
/// Subclass it as your extension's `NSExtensionPrincipalClass`; an empty subclass is enough:
///
/// ```swift
/// final class PacketTunnelProvider: XrayPacketTunnelProvider {}
/// ```
///
/// The share link is read from the start options (`startVPNTunnel(options: [XrayPacketTunnelProvider.linkKey: link])`),
/// falling back to `providerConfiguration[linkKey]` so Connect On Demand and restarts after a reboot work too.
///
/// Sockets opened by an extension never go through its own tunnel, which is how Xray's outbound
/// connections avoid looping back into it.
open class XrayPacketTunnelProvider: NEPacketTunnelProvider {
    /// Key for the share link, in start options and in `providerConfiguration`.
    public static let linkKey = "link"

    public let log = Logger(subsystem: "VLESSKit", category: "tunnel")
    private var core: Libv2rayCoreController?

    /// Config options. Override to change DNS, MTU or the IPv6 / QUIC rules.
    open var configOptions: XrayConfig.Options { .default }

    /// Override to build a config of your own (it must keep the `tun` inbound).
    open func makeConfig(for link: ShareLink) throws -> String {
        try XrayConfig.jsonString(link, options: configOptions)
    }

    override open func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let saved = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        guard let raw = (options?[Self.linkKey] as? String) ?? (saved?[Self.linkKey] as? String),
              let link = ShareLink.parse(raw) else {
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
                try self.startCore(link)
                completionHandler(nil)
            } catch {
                self.log.error("connect failed: \(error.localizedDescription, privacy: .public)")
                completionHandler(error)
            }
        }
    }

    override open func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        stopCore()
        completionHandler()
    }

    /// Called for every status line Xray emits.
    open func coreDidEmit(code: Int, message: String) {
        log.info("xray[\(code)] \(message, privacy: .public)")
    }

    /// IPv4 and IPv6 default routes, so neither can bypass the tunnel (with the default options Xray then refuses IPv6).
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

    private func startCore(_ link: ShareLink) throws {
        guard let fd = tunnelFileDescriptor else { throw VLESSKitError.noTunnelDescriptor }
        let config = try makeConfig(for: link)
        Libv2rayInitCoreEnv(FileManager.default.temporaryDirectory.path, "")

        let controller = core ?? Libv2rayNewCoreController(CoreCallback(owner: self))
        guard let controller else { throw VLESSKitError.coreFailed }
        core = controller
        if controller.isRunning { try controller.stopLoop() }
        try controller.startLoop(config, tunFd: fd)
        guard controller.isRunning else { throw VLESSKitError.coreFailed }
    }

    private func stopCore() {
        guard let core, core.isRunning else { return }
        do { try core.stopLoop() } catch { log.warning("stopLoop: \(error.localizedDescription, privacy: .public)") }
    }

    /// NetworkExtension doesn't hand out the utun fd; find it by asking each open socket for its utun name
    /// (the way Xray's own README and WireGuard do it).
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

/// Versions of the bundled core, e.g. for an About screen.
public enum XrayCore {
    public static var version: String { Libv2rayCheckVersionX() }
}

private final class CoreCallback: NSObject, Libv2rayCoreCallbackHandlerProtocol {
    private weak var owner: XrayPacketTunnelProvider?

    init(owner: XrayPacketTunnelProvider) { self.owner = owner }

    func startup() -> Int { 0 }
    func shutdown() -> Int { 0 }

    func onEmitStatus(_ code: Int, p1 message: String?) -> Int {
        owner?.coreDidEmit(code: code, message: message ?? "")
        return 0
    }
}
#endif

import Foundation

public enum VLESSKitError: LocalizedError {
    case unsupportedLink, noTunnelDescriptor, coreFailed

    public var errorDescription: String? {
        switch self {
        case .unsupportedLink: return "Unsupported server link"
        case .noTunnelDescriptor: return "Couldn't open the tunnel"
        case .coreFailed: return "Xray core failed to start"
        }
    }
}
