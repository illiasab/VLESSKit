import XCTest
@testable import VLESSKitTunnel

final class CoreTests: XCTestCase {
    #if os(iOS)
    func testCoreLoads() {
        XCTAssertTrue(XrayCore.version.contains("Xray"), XrayCore.version)
    }
    #endif

    func testLinkKeysMatch() {
        #if canImport(NetworkExtension)
        XCTAssertEqual(VLESSTunnelManager.linkKey, "link")
        #endif
    }
}
