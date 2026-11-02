import Foundation
import NetworkExtension
import Observation
import VLESSKitTunnel

struct DemoServer: Identifiable, Equatable {
    let link: String
    let parsed: ProxyLink

    var id: String { link }
    var flag: String {
        guard let code = ProxyLink.splitFlag(parsed.remark).code else { return "🌐" }
        return String(String.UnicodeScalarView(code.unicodeScalars.compactMap { Unicode.Scalar(0x1F1A5 + $0.value) }))
    }
    var name: String {
        let name = ProxyLink.splitFlag(parsed.remark).name
        return name.isEmpty ? parsed.host : name
    }
    var details: String {
        switch parsed.proto {
        case .vless: return ["vless", parsed.security, parsed.network, parsed["flow"]].compactMap { $0 }.joined(separator: " · ")
        case .shadowsocks: return "ss · \(parsed.method)"
        case .hysteria2: return ["hy2 · quic", parsed["obfs"].map { "\($0) obfs" }].compactMap { $0 }.joined(separator: " · ")
        }
    }
}

struct LogLine: Identifiable {
    enum Kind { case info, ok, warn }
    let id = UUID()
    let text: String
    let kind: Kind
}

@Observable
final class DemoModel {
    enum Status { case off, connecting, on }

    private(set) var servers: [DemoServer] = []
    var proto: ProxyLink.Proto = .vless { didSet { if let first = visibleServers.first, selected?.parsed.proto != proto { selected = first } } }
    var selected: DemoServer?
    private(set) var status: Status = .off
    private(set) var connectedSince: Date?
    private(set) var ipLine = "Tap to connect"
    private(set) var traffic = XrayTraffic()
    private(set) var latency: [String: Int?] = [:]
    private(set) var log: [LogLine] = []

    static let tunnelBundleId = "com.example.vlesskit.demo.tunnel"
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private let proxy = XrayLocalProxy()
    private let vpn = VLESSTunnelManager(extensionBundleId: DemoModel.tunnelBundleId, name: "VLESSKit Demo")
    private var poller: Task<Void, Never>?
    private var statusWatcher: Task<Void, Never>?

    var visibleServers: [DemoServer] { servers.filter { $0.parsed.proto == proto } }

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: "servers") ?? []
        let fromLaunch = ProcessInfo.processInfo.environment["VLESSKIT_DEMO_LINKS"]?
            .split(whereSeparator: \.isWhitespace).map(String.init) ?? []
        for link in saved + fromLaunch { add(link, persist: false) }
        persist()
        selected = visibleServers.first ?? servers.first
        if let selected { proto = selected.parsed.proto }

        append("[core] VLESSKit initialized · \(XrayCore.version.split(separator: "(").first.map(String.init) ?? "")")
        append("[core] 3 protocols registered")
        append(Self.isSimulator ? "[mode] simulator: local proxy, no VPN" : "[tun] waiting for start…")
        Task { await measureLatency() }

        // Launch with VLESSKIT_DEMO_CONNECT=<server index> to connect without tapping (used for automated checks).
        if let index = ProcessInfo.processInfo.environment["VLESSKIT_DEMO_CONNECT"].flatMap(Int.init), servers.indices.contains(index) {
            proto = servers[index].parsed.proto
            selected = servers[index]
            Task { await connect() }
        }
    }

    // MARK: Servers

    @discardableResult
    func add(_ text: String, persist save: Bool = true) -> Int {
        var added = 0
        for line in text.split(whereSeparator: \.isNewline) {
            let link = line.trimmingCharacters(in: .whitespaces)
            guard let parsed = ProxyLink.parse(link), !servers.contains(where: { $0.link == link }) else { continue }
            servers.append(DemoServer(link: link, parsed: parsed))
            added += 1
        }
        if save { persist() }
        return added
    }

    func paste(_ text: String?) {
        let added = add(text ?? "")
        append(added > 0 ? "[cfg] added \(added) server(s)" : "[cfg] clipboard has no vless/ss/hy2 link", added > 0 ? .ok : .warn)
        if let last = servers.last, added > 0 {
            proto = last.parsed.proto
            selected = last
            Task { await measureLatency() }
        }
    }

    func remove(_ server: DemoServer) {
        servers.removeAll { $0 == server }
        if selected == server { selected = visibleServers.first }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(servers.map(\.link), forKey: "servers")
    }

    func measureLatency() async {
        for server in visibleServers {
            let link = server.parsed
            let ms = await Task.detached { try? XrayCore.measureDelay(link) }.value
            latency[server.id] = .some(ms)
        }
    }

    // MARK: Connection

    func toggle() {
        switch status {
        case .connecting: return
        case .on: Task { await disconnect() }
        case .off: Task { await connect() }
        }
    }

    private func connect() async {
        guard let server = selected else {
            append("[cfg] add a server first: copy a link, tap Paste", .warn)
            return
        }
        status = .connecting
        ipLine = "Handshaking…"
        traffic = XrayTraffic()
        append("[\(server.parsed.proto.rawValue.lowercased())] dialing \(server.parsed.host):\(server.parsed.port)")
        do {
            if Self.isSimulator {
                try await proxy.start(server.parsed)
                append("[core] proxy up · 127.0.0.1:\(proxy.httpPort)", .ok)
                try await didConnect(session: URLSession(configuration: proxy.sessionConfiguration))
            } else {
                try await vpn.connect(server.link)
                watchTunnel()
            }
        } catch {
            fail(error)
        }
    }

    private func watchTunnel() {
        statusWatcher?.cancel()
        statusWatcher = Task {
            for _ in 0..<150 {
                try? await Task.sleep(for: .milliseconds(200))
                switch vpn.status {
                case .connected:
                    append("[tun] utun up · routing all traffic", .ok)
                    do { try await didConnect(session: .shared) } catch { fail(error) }
                    return
                case .disconnected, .invalid:
                    fail(await vpn.lastError() ?? VLESSKitError.coreFailed)
                    return
                default:
                    continue
                }
            }
            fail(URLError(.timedOut))
        }
    }

    /// Fetches the public IP through the proxy; seeing the server's IP is the proof the tunnel works.
    private func didConnect(session: URLSession) async throws {
        var request = URLRequest(url: URL(string: "https://ipinfo.io/json")!)
        request.timeoutInterval = 15
        let (data, _) = try await session.data(for: request)
        let info = try JSONDecoder().decode(IPInfo.self, from: data)
        status = .on
        connectedSince = Date()
        ipLine = "IP \(info.ip) · \(info.country ?? "?")"
        append("[net] exit IP \(info.ip) \(info.city ?? "")", .ok)
        startPolling()
    }

    private func disconnect() async {
        poller?.cancel()
        statusWatcher?.cancel()
        if Self.isSimulator { try? await proxy.stop() } else { await vpn.disconnect() }
        status = .off
        connectedSince = nil
        ipLine = "Tap to connect"
        append("[tun] tunnel stopped", .warn)
    }

    private func fail(_ error: Error) {
        poller?.cancel()
        Task { if Self.isSimulator { try? await proxy.stop() } else { await vpn.disconnect() } }
        status = .off
        connectedSince = nil
        ipLine = "Tap to connect"
        append("[err] \(error.localizedDescription)", .warn)
    }

    private func startPolling() {
        poller?.cancel()
        poller = Task {
            while !Task.isCancelled {
                if Self.isSimulator {
                    traffic = await proxy.traffic()
                } else if let value = await vpn.traffic() {
                    traffic = value
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func append(_ text: String, _ kind: LogLine.Kind = .info) {
        log.append(LogLine(text: text, kind: kind))
        if log.count > 5 { log.removeFirst(log.count - 5) }
    }
}

private struct IPInfo: Decodable {
    let ip: String
    let country: String?
    let city: String?
}
