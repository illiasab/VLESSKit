import Foundation

/// Bytes sent and received through the proxy outbound.
public struct XrayTraffic: Codable, Equatable, Sendable {
    public var uplink: Int64
    public var downlink: Int64

    public init(uplink: Int64 = 0, downlink: Int64 = 0) {
        self.uplink = uplink
        self.downlink = downlink
    }

    /// Adds a core stats line (`tag,uplink|downlink,bytes;…`), counting only the `proxy` outbound.
    public mutating func add(statsLine: String) {
        for entry in statsLine.split(separator: ";") {
            let parts = entry.split(separator: ",")
            guard parts.count == 3, parts[0] == "proxy", let bytes = Int64(parts[2]) else { continue }
            switch parts[1] {
            case "uplink": uplink += bytes
            case "downlink": downlink += bytes
            default: break
            }
        }
    }
}
