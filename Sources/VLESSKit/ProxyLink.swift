import Foundation

/// A parsed `vless://`, `ss://` or `hysteria2://` (`hy2://`) share link.
public struct ProxyLink: Equatable, Hashable, Sendable {
    public enum Proto: String, Sendable { case vless = "Vless", shadowsocks = "Shadowsocks", hysteria2 = "Hysteria2" }

    public let proto: Proto
    /// VLESS: UUID. Shadowsocks: password. Hysteria2: auth.
    public let secret: String
    public let host: String
    public let port: Int
    public let params: [String: String]
    public let remark: String
    public let method: String

    public init(proto: Proto, secret: String, host: String, port: Int, params: [String: String] = [:], remark: String = "", method: String = "") {
        self.proto = proto
        self.secret = secret
        self.host = host
        self.port = port
        self.params = params
        self.remark = remark
        self.method = method
    }

    public init?(_ link: String) {
        guard let parsed = Self.parse(link) else { return nil }
        self = parsed
    }

    public var network: String { params["type"].map { $0.lowercased() }.flatMap { $0.isEmpty ? nil : $0 } ?? "tcp" }
    public var security: String { params["security"].map { $0.lowercased() }.flatMap { $0.isEmpty ? nil : $0 } ?? "none" }

    public subscript(key: String) -> String? { params[key].flatMap { $0.isEmpty ? nil : $0 } }

    public var transportLabel: String {
        switch proto {
        case .vless: return security == "none" ? network.uppercased() : "\(network.uppercased()) · \(security.uppercased())"
        case .shadowsocks: return "SHADOWSOCKS"
        case .hysteria2: return self["obfs"] != nil ? "HY2 · OBFS" : "HYSTERIA2"
        }
    }

    public var isUDPOnly: Bool { proto == .hysteria2 }

    public static func parse(_ link: String) -> ProxyLink? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let schemeEnd = trimmed.range(of: "://") else { return nil }
        let scheme = trimmed[..<schemeEnd.lowerBound].lowercased()
        guard !scheme.isEmpty else { return nil }
        var rest = String(trimmed[schemeEnd.upperBound...])
        let remark = rest.after("#").map(decode) ?? ""
        rest = rest.before("#")
        let params = queryParams(rest.after("?") ?? "")
        rest = rest.before("?")
        while rest.hasSuffix("/") { rest.removeLast() }

        switch scheme {
        case "vless":
            guard let (user, endpoint) = splitUser(rest) else { return nil }
            let uuid = decode(user)
            guard !uuid.isEmpty, let (host, port) = hostPort(endpoint) else { return nil }
            return ProxyLink(proto: .vless, secret: uuid, host: host, port: port, params: params, remark: remark)
        case "ss":
            return parseShadowsocks(rest, params: params, remark: remark)
        case "hysteria2", "hy2":
            guard let (user, endpoint) = splitUser(rest), let (host, port) = hostPort(endpoint) else { return nil }
            return ProxyLink(proto: .hysteria2, secret: decode(user), host: host, port: port, params: params, remark: remark)
        default:
            return nil
        }
    }

    /// "🇩🇪 Frankfurt" → ("DE", "Frankfurt"); a remark without a leading flag → (nil, remark).
    public static func splitFlag(_ remark: String) -> (code: String?, name: String) {
        let scalars = Array(remark.trimmingCharacters(in: .whitespaces).unicodeScalars)
        let isIndicator = { (s: Unicode.Scalar) in (0x1F1E6...0x1F1FF).contains(s.value) }
        if scalars.count >= 2, isIndicator(scalars[0]), isIndicator(scalars[1]) {
            let letter = { (s: Unicode.Scalar) in Character(Unicode.Scalar(UInt8(65 + s.value - 0x1F1E6))) }
            let code = String([letter(scalars[0]), letter(scalars[1])])
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars.dropFirst(2))
            let name = String(view).trimmingCharacters(in: .whitespaces)
            return (code, name.isEmpty ? code : name)
        }
        return (nil, remark.trimmingCharacters(in: .whitespaces))
    }

    private static func parseShadowsocks(_ rest: String, params: [String: String], remark: String) -> ProxyLink? {
        let userInfo: String
        let endpoint: String
        if let (encodedUser, ep) = splitUser(rest) {
            let user = decode(encodedUser)
            guard let info = user.contains(":") ? user : base64(user) else { return nil }
            userInfo = info
            endpoint = ep
        } else {
            // Legacy: everything base64-encoded.
            guard let whole = base64(rest), let at = whole.lastIndex(of: "@") else { return nil }
            userInfo = String(whole[..<at])
            endpoint = String(whole[whole.index(after: at)...])
        }
        guard let colon = userInfo.firstIndex(of: ":") else { return nil }
        let method = String(userInfo[..<colon])
        let password = String(userInfo[userInfo.index(after: colon)...])
        guard !method.isEmpty, !password.isEmpty, let (host, port) = hostPort(endpoint) else { return nil }
        return ProxyLink(proto: .shadowsocks, secret: password, host: host, port: port, params: params, remark: remark, method: method)
    }

    private static func splitUser(_ rest: String) -> (String, String)? {
        guard let at = rest.lastIndex(of: "@"), at > rest.startIndex else { return nil }
        return (String(rest[..<at]), String(rest[rest.index(after: at)...]))
    }

    private static func hostPort(_ authority: String) -> (String, Int)? {
        let host: String
        let portText: String
        if authority.hasPrefix("[") {
            host = authority.dropFirst().before("]")
            portText = authority.after("]:") ?? ""
        } else if let colon = authority.lastIndex(of: ":") {
            host = String(authority[..<colon])
            portText = String(authority[authority.index(after: colon)...])
        } else {
            return nil
        }
        guard let port = Int(portText), (1...65535).contains(port), !host.isEmpty else { return nil }
        return (host, port)
    }

    private static func queryParams(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") where !pair.isEmpty {
            let text = String(pair)
            result[decode(text.before("="))] = decode(text.after("=") ?? "")
        }
        return result
    }

    private static func base64(_ value: String) -> String? {
        var normalized = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        normalized += String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        guard let data = Data(base64Encoded: normalized), let text = String(data: data, encoding: .utf8) else { return nil }
        return text.unicodeScalars.allSatisfy { (0x20...0x7e).contains($0.value) } ? text : nil
    }

    /// Leaves `+` alone: it is common in passwords and base64.
    private static func decode(_ value: String) -> String { value.removingPercentEncoding ?? value }
}

private extension StringProtocol {
    func before(_ separator: String) -> String {
        range(of: separator).map { String(self[..<$0.lowerBound]) } ?? String(self)
    }

    func after(_ separator: String) -> String? {
        range(of: separator).map { String(self[$0.upperBound...]) }
    }
}

@available(*, deprecated, renamed: "ProxyLink", message: "Renamed so it doesn't clash with SwiftUI.ShareLink.")
public typealias ShareLink = ProxyLink
