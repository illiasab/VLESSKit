import Foundation

/// Builds a complete Xray-core JSON config: a TUN inbound (the utun fd NetworkExtension creates) and a
/// VLESS / Shadowsocks / Hysteria2 outbound from a ``ShareLink``.
///
/// DNS queries arriving on the TUN are answered by Xray's DNS module, which resolves over DNS-over-HTTPS
/// through the proxy, so nothing leaks to the local resolver.
///
/// With the default ``Options`` two rules keep connections from stalling:
///  - IPv6 is refused at once instead of being sent to servers that usually have no IPv6, so apps fall
///    back to IPv4 immediately rather than after a timeout, and IPv6 still can't leak.
///  - On VLESS (TCP-based transports), QUIC (UDP 443) is refused so browsers and video apps fall back to
///    TCP instead of tunnelling QUIC inside TCP, which stalls.
public enum XrayConfig {
    public typealias JSON = [String: Any]

    public struct Options: Sendable {
        /// MTU of the TUN interface. Use the same value in `NEPacketTunnelNetworkSettings`.
        public var mtu: Int
        /// DNS-over-HTTPS servers Xray resolves with, through the proxy.
        public var dohServers: [String]
        /// Refuse IPv6 immediately.
        public var blockIPv6: Bool
        /// Refuse UDP 443 when the outbound is VLESS.
        public var blockQUICOverTCP: Bool
        /// Send private / link-local ranges straight out instead of through the proxy.
        public var bypassPrivateRanges: Bool
        /// Xray log level: debug, info, warning, error, none.
        public var logLevel: String

        public init(
            mtu: Int = 1500,
            dohServers: [String] = ["https://1.1.1.1/dns-query", "https://8.8.8.8/dns-query"],
            blockIPv6: Bool = true,
            blockQUICOverTCP: Bool = true,
            bypassPrivateRanges: Bool = true,
            logLevel: String = "warning"
        ) {
            self.mtu = mtu
            self.dohServers = dohServers
            self.blockIPv6 = blockIPv6
            self.blockQUICOverTCP = blockQUICOverTCP
            self.bypassPrivateRanges = bypassPrivateRanges
            self.logLevel = logLevel
        }

        public static let `default` = Options()
    }

    /// Plain DNS addresses to give iOS as the tunnel's resolvers. Queries to them reach the TUN and are
    /// answered by Xray, so their actual value only matters for apps that hard-code a resolver.
    public static let tunnelDNS = ["1.1.1.1", "8.8.8.8"]

    public static func build(_ link: ShareLink, options: Options = .default) -> JSON {
        var rules: [JSON] = [["inboundTag": ["tun"], "port": "53", "outboundTag": "dns-out"]]
        if options.bypassPrivateRanges {
            rules.append(["ip": privateRanges, "outboundTag": "direct"])
        }
        if options.blockIPv6 {
            rules.append(["ip": ["::/0"], "outboundTag": "block"])
        }
        if options.blockQUICOverTCP, link.proto == .vless {
            rules.append(["network": "udp", "port": "443", "outboundTag": "block"])
        }
        var dns: JSON = ["servers": options.dohServers]
        if options.blockIPv6 { dns["queryStrategy"] = "UseIPv4" }
        return [
            "log": ["loglevel": options.logLevel],
            "dns": dns,
            "inbounds": [tunInbound(mtu: options.mtu)],
            "outbounds": [proxyOutbound(link), direct, dnsOut, block],
            "routing": ["domainStrategy": "AsIs", "rules": rules],
        ]
    }

    public static func jsonString(_ link: ShareLink, options: Options = .default) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: build(link, options: options), options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    /// Only the outbound (tag `proxy`), for embedding in a config of your own.
    public static func proxyOutbound(_ link: ShareLink) -> JSON {
        var outbound: JSON
        switch link.proto {
        case .vless: outbound = vless(link)
        case .shadowsocks: outbound = shadowsocks(link)
        case .hysteria2: outbound = hysteria2(link)
        }
        outbound["tag"] = "proxy"
        return outbound
    }

    /// Share-link `fragment=length,delay,packets` (e.g. `1-1,0-1,tlshello`) → finalmask TCP fragment.
    /// Both spellings are written: `length`/`delay` (what most clients emit) and `lengths`/`delays`
    /// (current Xray docs); Xray ignores the one it doesn't know.
    public static func fragment(_ link: ShareLink) -> JSON? {
        guard let parts = link["fragment"]?.components(separatedBy: ",").map({ $0.trimmingCharacters(in: .whitespaces) }),
              parts.count == 3, !parts.contains(where: \.isEmpty) else { return nil }
        let (length, delay, packets) = (parts[0], parts[1], parts[2])
        let settings: JSON = ["packets": packets, "length": length, "delay": delay, "lengths": [length], "delays": [delay]]
        return ["tcp": [["type": "fragment", "settings": settings]]]
    }

    private static func tunInbound(mtu: Int) -> JSON {
        [
            "tag": "tun",
            "protocol": "tun",
            "settings": ["name": "xray0", "MTU": mtu, "userLevel": 8],
            "sniffing": ["enabled": true, "destOverride": ["http", "tls", "quic"]],
        ]
    }

    private static func vless(_ link: ShareLink) -> JSON {
        var user: JSON = ["id": link.secret, "encryption": link["encryption"] ?? "none", "level": 8]
        if let flow = link["flow"] { user["flow"] = flow }
        return [
            "protocol": "vless",
            "settings": ["vnext": [["address": link.host, "port": link.port, "users": [user]]]],
            "streamSettings": streamSettings(link),
            "mux": ["enabled": false],
        ]
    }

    private static func shadowsocks(_ link: ShareLink) -> JSON {
        var stream: JSON = ["network": "tcp"]
        if let mask = fragment(link) { stream["finalmask"] = mask }
        return [
            "protocol": "shadowsocks",
            "settings": ["servers": [[
                "address": link.host, "port": link.port, "method": link.method, "password": link.secret, "level": 8,
            ]]],
            "streamSettings": stream,
        ]
    }

    /// Xray 26 runs Hysteria2 as protocol "hysteria" v2 over its own QUIC transport; salamander and port
    /// hopping live in finalmask.
    private static func hysteria2(_ link: ShareLink) -> JSON {
        var finalmask: JSON = [:]
        if link["obfs"] == "salamander" {
            finalmask["udp"] = [["type": "salamander", "settings": ["password": link["obfs-password"] ?? ""]]]
        }
        if let ports = link["mport"] {
            finalmask["quicParams"] = ["udpHop": ["ports": ports, "interval": 30]]
        }
        var stream: JSON = [
            "network": "hysteria",
            "hysteriaSettings": ["version": 2, "auth": link.secret],
            "security": "tls",
            "tlsSettings": [
                "serverName": link["sni"] ?? link.host,
                "alpn": (link["alpn"] ?? "h3").components(separatedBy: ","),
                "allowInsecure": link["insecure"] == "1" || link["insecure"] == "true",
            ] as JSON,
        ]
        if !finalmask.isEmpty { stream["finalmask"] = finalmask }
        return [
            "protocol": "hysteria",
            "settings": ["version": 2, "address": link.host, "port": link.port],
            "streamSettings": stream,
        ]
    }

    private static func streamSettings(_ link: ShareLink) -> JSON {
        var stream: JSON = ["network": link.network, "security": link.security]
        let hostHeader = link["host"]
        func pathSettings() -> JSON {
            var settings: JSON = ["path": link["path"] ?? "/"]
            if let hostHeader { settings["host"] = hostHeader }
            return settings
        }
        switch link.network {
        case "ws":
            stream["wsSettings"] = pathSettings()
        case "httpupgrade":
            stream["httpupgradeSettings"] = pathSettings()
        case "xhttp", "splithttp":
            var settings = pathSettings()
            settings["mode"] = link["mode"] ?? "auto"
            if let extra = link["extra"]?.data(using: .utf8),
               let object = (try? JSONSerialization.jsonObject(with: extra)) as? JSON {
                settings["extra"] = object
            }
            stream["network"] = "xhttp"
            stream["xhttpSettings"] = settings
        case "grpc":
            stream["grpcSettings"] = ["serviceName": link["serviceName"] ?? "", "multiMode": link["mode"] == "multi"]
        case "tcp", "raw":
            if link["headerType"] == "http" {
                stream["tcpSettings"] = ["header": ["type": "http", "request": [
                    "path": [link["path"] ?? "/"],
                    "headers": ["Host": [hostHeader ?? link.host]],
                ]]]
            }
        default:
            break
        }

        let sni = link["sni"] ?? hostHeader ?? link.host
        let fingerprint = link["fp"] ?? "chrome"
        switch link.security {
        case "tls":
            var tls: JSON = [
                "serverName": sni,
                "fingerprint": fingerprint,
                "allowInsecure": link["allowInsecure"] == "1" || link["allowInsecure"] == "true",
            ]
            if let alpn = link["alpn"] { tls["alpn"] = alpn.components(separatedBy: ",") }
            stream["tlsSettings"] = tls
        case "reality":
            stream["realitySettings"] = [
                "serverName": sni,
                "fingerprint": fingerprint,
                "publicKey": link["pbk"] ?? "",
                "shortId": link["sid"] ?? "",
                "spiderX": link["spx"] ?? "",
            ]
        default:
            break
        }
        if let mask = fragment(link) { stream["finalmask"] = mask }
        return stream
    }

    private static let direct: JSON = ["tag": "direct", "protocol": "freedom"]
    private static let dnsOut: JSON = ["tag": "dns-out", "protocol": "dns"]
    /// Closes the connection immediately, so the app retries another way at once.
    private static let block: JSON = ["tag": "block", "protocol": "blackhole"]

    /// Spelled out instead of `geoip:private` so no geoip.dat has to be shipped.
    private static let privateRanges = [
        "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8", "169.254.0.0/16", "100.64.0.0/10", "fc00::/7", "fe80::/10",
    ]
}
