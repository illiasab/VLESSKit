import Foundation
import XCTest
@testable import VLESSKit

final class ProxyLinkTests: XCTestCase {
    func testVlessXhttpTLS() throws {
        let link = try XCTUnwrap(ProxyLink.parse(
            "vless://8f3c6c3e-1111-4222-8333-944455556666@example.com:443?type=xhttp&security=tls&sni=cdn.example.com&alpn=h2,http%2F1.1&fp=chrome&path=%2Fx&fragment=1-1,0-1,tlshello#%F0%9F%87%A9%F0%9F%87%AA%20Frankfurt"
        ))
        XCTAssertEqual(link.proto, .vless)
        XCTAssertEqual(link.secret, "8f3c6c3e-1111-4222-8333-944455556666")
        XCTAssertEqual(link.host, "example.com")
        XCTAssertEqual(link.port, 443)
        XCTAssertEqual(link.network, "xhttp")
        XCTAssertEqual(link.security, "tls")
        XCTAssertEqual(link["alpn"], "h2,http/1.1")
        XCTAssertEqual(link.transportLabel, "XHTTP · TLS")
        XCTAssertEqual(ProxyLink.splitFlag(link.remark).code, "DE")
        XCTAssertEqual(ProxyLink.splitFlag(link.remark).name, "Frankfurt")
    }

    func testVlessIPv6HostAndDefaults() throws {
        let link = try XCTUnwrap(ProxyLink("vless://id@[2001:db8::1]:8443"))
        XCTAssertEqual(link.host, "2001:db8::1")
        XCTAssertEqual(link.port, 8443)
        XCTAssertEqual(link.network, "tcp")
        XCTAssertEqual(link.security, "none")
    }

    func testShadowsocksSIP002AndLegacy() throws {
        let userInfo = Data("chacha20-ietf-poly1305:pa+ss".utf8).base64EncodedString()
        let sip002 = try XCTUnwrap(ProxyLink.parse("ss://\(userInfo)@1.2.3.4:8388#SS"))
        XCTAssertEqual(sip002.proto, .shadowsocks)
        XCTAssertEqual(sip002.method, "chacha20-ietf-poly1305")
        XCTAssertEqual(sip002.secret, "pa+ss")

        let whole = Data("aes-256-gcm:secret@5.6.7.8:443".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let legacy = try XCTUnwrap(ProxyLink.parse("ss://\(whole)"))
        XCTAssertEqual(legacy.method, "aes-256-gcm")
        XCTAssertEqual(legacy.host, "5.6.7.8")
        XCTAssertEqual(legacy.port, 443)
    }

    func testHysteria2() throws {
        let link = try XCTUnwrap(ProxyLink.parse("hy2://auth@hy.example.com:443/?sni=hy.example.com&obfs=salamander&obfs-password=pw&mport=20000-30000#HY"))
        XCTAssertEqual(link.proto, .hysteria2)
        XCTAssertEqual(link.secret, "auth")
        XCTAssertTrue(link.isUDPOnly)
        XCTAssertEqual(link.transportLabel, "HY2 · OBFS")
    }

    func testRejectsMalformed() {
        XCTAssertNil(ProxyLink.parse("vmess://abc"))
        XCTAssertNil(ProxyLink.parse("vless://@host:443"))
        XCTAssertNil(ProxyLink.parse("vless://id@host"))
        XCTAssertNil(ProxyLink.parse("vless://id@host:70000"))
        XCTAssertNil(ProxyLink.parse("not a link"))
    }
}

final class XrayConfigTests: XCTestCase {
    private func object(_ link: String, _ options: XrayConfig.Options = .default) throws -> [String: Any] {
        let json = try XrayConfig.jsonString(try XCTUnwrap(ProxyLink.parse(link)), options: options)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    private func rules(_ config: [String: Any]) -> [[String: Any]] {
        ((config["routing"] as? [String: Any])?["rules"] as? [[String: Any]]) ?? []
    }

    func testVlessRealityOutbound() throws {
        let config = try object("vless://id@h.com:443?type=tcp&security=reality&pbk=KEY&sid=ab&sni=www.apple.com&flow=xtls-rprx-vision")
        let outbound = try XCTUnwrap((config["outbounds"] as? [[String: Any]])?.first)
        XCTAssertEqual(outbound["tag"] as? String, "proxy")
        XCTAssertEqual(outbound["protocol"] as? String, "vless")
        let stream = try XCTUnwrap(outbound["streamSettings"] as? [String: Any])
        let reality = try XCTUnwrap(stream["realitySettings"] as? [String: Any])
        XCTAssertEqual(reality["publicKey"] as? String, "KEY")
        XCTAssertEqual(reality["serverName"] as? String, "www.apple.com")
        let vnext = try XCTUnwrap((outbound["settings"] as? [String: Any])?["vnext"] as? [[String: Any]])
        let user = try XCTUnwrap((vnext.first?["users"] as? [[String: Any]])?.first)
        XCTAssertEqual(user["flow"] as? String, "xtls-rprx-vision")
    }

    func testDefaultRulesBlockIPv6AndQUICOnVless() throws {
        let config = try object("vless://id@h.com:443?type=ws&security=tls")
        let rules = rules(config)
        XCTAssertTrue(rules.contains { ($0["ip"] as? [String]) == ["::/0"] && $0["outboundTag"] as? String == "block" })
        XCTAssertTrue(rules.contains { $0["network"] as? String == "udp" && $0["port"] as? String == "443" })
        XCTAssertEqual((config["dns"] as? [String: Any])?["queryStrategy"] as? String, "UseIPv4")
    }

    func testOptionsTurnRulesOff() throws {
        let config = try object("vless://id@h.com:443", .init(blockIPv6: false, blockQUICOverTCP: false, bypassPrivateRanges: false))
        XCTAssertEqual(rules(config).count, 1) // only DNS interception
        XCTAssertNil((config["dns"] as? [String: Any])?["queryStrategy"])
    }

    func testHysteria2DoesNotBlockQUIC() throws {
        let config = try object("hysteria2://a@h.com:443?obfs=salamander&obfs-password=pw&mport=20000-30000")
        XCTAssertFalse(rules(config).contains { $0["network"] as? String == "udp" })
        let outbound = try XCTUnwrap((config["outbounds"] as? [[String: Any]])?.first)
        XCTAssertEqual(outbound["protocol"] as? String, "hysteria")
        let mask = try XCTUnwrap((outbound["streamSettings"] as? [String: Any])?["finalmask"] as? [String: Any])
        XCTAssertNotNil(mask["udp"])
        XCTAssertNotNil(mask["quicParams"])
    }

    func testXhttpExtraAndFragment() throws {
        let extra = #"{"xPaddingBytes":"100-1000"}"#.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let config = try object("vless://id@h.com:443?type=xhttp&security=tls&extra=\(extra)&fragment=1-1,0-1,tlshello")
        let stream = try XCTUnwrap(((config["outbounds"] as? [[String: Any]])?.first)?["streamSettings"] as? [String: Any])
        let xhttp = try XCTUnwrap(stream["xhttpSettings"] as? [String: Any])
        XCTAssertEqual((xhttp["extra"] as? [String: Any])?["xPaddingBytes"] as? String, "100-1000")
        XCTAssertNotNil((stream["finalmask"] as? [String: Any])?["tcp"])
    }

    func testLocalProxyHasNoTunAndCountsTraffic() throws {
        let link = try XCTUnwrap(ProxyLink.parse("vless://id@h.com:443?type=ws&security=tls"))
        let config = XrayConfig.buildLocalProxy(link, socksPort: 1080, httpPort: 8080)
        let inbounds = try XCTUnwrap(config["inbounds"] as? [[String: Any]])
        XCTAssertEqual(inbounds.map { $0["protocol"] as? String }, ["socks", "http"])
        XCTAssertTrue(inbounds.allSatisfy { $0["listen"] as? String == "127.0.0.1" })
        XCTAssertFalse(rules(config).contains { $0["inboundTag"] != nil })
        XCTAssertNotNil(config["stats"])
        XCTAssertNoThrow(try XrayConfig.serialize(config))
    }

    func testTrafficStatsOff() throws {
        let config = XrayConfig.build(try XCTUnwrap(ProxyLink.parse("vless://id@h.com:443")), options: .init(trafficStats: false))
        XCTAssertNil(config["stats"])
        XCTAssertNil(config["policy"])
    }
}

final class XrayTrafficTests: XCTestCase {
    func testAccumulatesProxyOnly() {
        var traffic = XrayTraffic()
        traffic.add(statsLine: "proxy,uplink,100;proxy,downlink,2000;direct,downlink,999;")
        traffic.add(statsLine: "proxy,downlink,500;")
        XCTAssertEqual(traffic, XrayTraffic(uplink: 100, downlink: 2500))
        traffic.add(statsLine: "")
        XCTAssertEqual(traffic.downlink, 2500)
    }
}
