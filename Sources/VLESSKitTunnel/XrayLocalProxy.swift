#if os(iOS) && canImport(Libv2ray)
import Foundation

/// Runs Xray in your app process with local SOCKS5 and HTTP proxies instead of a VPN. Works in the
/// simulator, where packet tunnels can't run; route a `URLSession` through it with ``sessionConfiguration``.
public actor XrayLocalProxy {
    public let socksPort: Int
    public let httpPort: Int
    private lazy var engine = XrayEngine { [weak self] code, message in
        guard let self else { return }
        Task { await self.onStatus?(code, message) }
    }
    private var onStatus: ((Int, String) -> Void)?

    public init(socksPort: Int = 10808, httpPort: Int = 10809) {
        self.socksPort = socksPort
        self.httpPort = httpPort
    }

    public var isRunning: Bool { engine.isRunning }

    public func setStatusHandler(_ handler: @escaping @Sendable (Int, String) -> Void) {
        onStatus = handler
    }

    public func start(_ link: ProxyLink, options: XrayConfig.Options = .default) throws {
        let config = XrayConfig.buildLocalProxy(link, socksPort: socksPort, httpPort: httpPort, options: options)
        try engine.start(config: try XrayConfig.serialize(config), tunFd: 0)
    }

    public func stop() throws {
        try engine.stop()
    }

    public func traffic() -> XrayTraffic {
        engine.refreshTraffic()
    }

    /// A session configuration that sends HTTP and HTTPS through the local proxy.
    public nonisolated var sessionConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [
            "HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": httpPort,
            "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": httpPort,
        ]
        return configuration
    }
}
#endif
