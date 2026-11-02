#if os(iOS) && canImport(Libv2ray)
import Foundation
import Libv2ray
@_exported import VLESSKit

public enum XrayCore {
    public static var version: String { Libv2rayCheckVersionX() }

    /// Round-trip in ms of an HTTP request made through `link`, using a short-lived core. Blocks; call it off the main thread.
    public static func measureDelay(_ link: ProxyLink, url: String = "https://www.gstatic.com/generate_204") throws -> Int {
        let config = try XrayConfig.jsonString(link, options: .init(trafficStats: false))
        var ms: Int64 = 0
        var error: NSError?
        guard Libv2rayMeasureOutboundDelay(config, url, &ms, &error), error == nil, ms >= 0 else {
            throw error ?? VLESSKitError.coreFailed
        }
        return Int(ms)
    }
}

/// One running Xray instance. Not thread-safe; use it from one queue or actor.
final class XrayEngine {
    private var controller: Libv2rayCoreController?
    private let callback: CoreCallback
    private(set) var traffic = XrayTraffic()

    init(onStatus: @escaping (Int, String) -> Void) {
        callback = CoreCallback(onStatus: onStatus)
    }

    var isRunning: Bool { controller?.isRunning ?? false }

    /// `tunFd` 0 runs without a TUN.
    func start(config: String, tunFd: Int32) throws {
        Libv2rayInitCoreEnv(FileManager.default.temporaryDirectory.path, "")
        let controller = controller ?? Libv2rayNewCoreController(callback)
        guard let controller else { throw VLESSKitError.coreFailed }
        self.controller = controller
        if controller.isRunning { try controller.stopLoop() }
        traffic = XrayTraffic()
        try controller.startLoop(config, tunFd: tunFd)
        guard controller.isRunning else { throw VLESSKitError.coreFailed }
    }

    func stop() throws {
        guard let controller, controller.isRunning else { return }
        try controller.stopLoop()
    }

    func refreshTraffic() -> XrayTraffic {
        if let controller, controller.isRunning {
            traffic.add(statsLine: controller.queryAllOutboundTrafficStats())
        }
        return traffic
    }
}

private final class CoreCallback: NSObject, Libv2rayCoreCallbackHandlerProtocol {
    private let onStatus: (Int, String) -> Void

    init(onStatus: @escaping (Int, String) -> Void) { self.onStatus = onStatus }

    func startup() -> Int { 0 }
    func shutdown() -> Int { 0 }

    func onEmitStatus(_ code: Int, p1 message: String?) -> Int {
        onStatus(code, message ?? "")
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
