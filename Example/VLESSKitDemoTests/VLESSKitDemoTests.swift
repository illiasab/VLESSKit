import XCTest
import VLESSKitTunnel
@testable import VLESSKitDemo

final class VLESSKitDemoTests: XCTestCase {
    func testServerDisplay() throws {
        let link = "vless://id@nl.example.com:443?type=tcp&security=reality&flow=xtls-rprx-vision#%F0%9F%87%B3%F0%9F%87%B1%20Amsterdam%20%C2%B7%20NL-01"
        let server = DemoServer(link: link, parsed: try XCTUnwrap(ProxyLink.parse(link)))
        XCTAssertEqual(server.flag, "🇳🇱")
        XCTAssertEqual(server.name, "Amsterdam · NL-01")
        XCTAssertEqual(server.details, "vless · reality · tcp · xtls-rprx-vision")
    }

    func testCoreLoads() {
        XCTAssertTrue(XrayCore.version.contains("Xray"))
    }
}
