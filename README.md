# VLESSKit

A Swift package for building VLESS, Shadowsocks and Hysteria2 VPN apps on iOS with
[Xray-core](https://github.com/XTLS/Xray-core) running inside a Network Extension.

- **`VLESSKit`**: share-link parsing and Xray config generation. Pure Swift, iOS and macOS, no binary.
- **`VLESSKitTunnel`**: a ready `NEPacketTunnelProvider` that runs Xray in-process on the utun file
  descriptor (no tun2socks), plus `VLESSTunnelManager` to install and start the VPN from your app.
  Also a local-proxy mode for the simulator, latency checks and traffic counters.

Tested against live VLESS servers (TLS over xhttp and WebSocket). A runnable SwiftUI demo is in
[`Example/`](Example).

## Supported links

| Scheme | Transports and options |
|---|---|
| `vless://` | `tcp`/`raw` (incl. HTTP header), `ws`, `httpupgrade`, `grpc`, `xhttp` (with `extra` JSON); `none`, `tls`, `reality`; `flow`, `fp`, `alpn`, `sni`, `fragment` |
| `ss://` | SIP002 and legacy base64 |
| `hysteria2://`, `hy2://` | `sni`, `insecure`, salamander `obfs`, port hopping (`mport`) |

## Install

```swift
.package(url: "https://github.com/illiasab/VLESSKit.git", from: "0.2.0")
```

Add `VLESSKitTunnel` to your **packet-tunnel extension** target, and `VLESSKitTunnel` (or only
`VLESSKit`) to your **app** target. The Xray core (a 40 MB zip) is downloaded from the GitHub release
automatically. It's linked statically and adds roughly 35 MB to a built app.

Requirements: iOS 16+, Xcode 16+, and the *Network Extensions → Packet Tunnel* capability on both
targets (a paid Apple developer account is needed for it).

## Use

**Extension.** Set this class as `NSExtensionPrincipalClass` in the extension's Info.plist:

```swift
import VLESSKitTunnel

final class PacketTunnelProvider: XrayPacketTunnelProvider {}
```

**App:**

```swift
import VLESSKitTunnel

let vpn = VLESSTunnelManager(extensionBundleId: "com.example.app.tunnel", name: "My VPN")

try await vpn.connect("vless://uuid@example.com:443?type=ws&security=tls&path=%2Fws#Frankfurt")
// vpn.status is an NEVPNStatus, published for SwiftUI.
await vpn.disconnect()
```

**Traffic and latency:**

```swift
let traffic = await vpn.traffic()                        // XrayTraffic(uplink:downlink:) in bytes
let ms = try XrayCore.measureDelay(ProxyLink(link)!)     // blocking; call off the main thread
```

**In the simulator** packet tunnels can't run, so run the core in your app as a local proxy:

```swift
let proxy = XrayLocalProxy()                             // SOCKS 127.0.0.1:10808, HTTP :10809
try await proxy.start(ProxyLink(link)!)
let session = URLSession(configuration: proxy.sessionConfiguration)
let (data, _) = try await session.data(from: URL(string: "https://ipinfo.io/json")!)
```

**Config only**, e.g. to run Xray yourself:

```swift
import VLESSKit

let link = ProxyLink("hy2://auth@example.com:443?obfs=salamander&obfs-password=pw")!
let json = try XrayConfig.jsonString(link)
```

`ProxyLink` was called `ShareLink` in 0.1.0; it was renamed because it clashed with SwiftUI's
`ShareLink`. The old name still works but is deprecated.

## Example app

`Example/VLESSKitDemo.xcodeproj` is a one-screen SwiftUI app with a connect button, server list,
latency, traffic and a log. Paste a `vless://`, `ss://` or `hy2://` link and tap connect. In the
simulator it runs the local proxy and shows the server's exit IP; on a device it runs the real VPN
(set your team and bundle IDs first).

## Defaults that keep connections from stalling

`XrayConfig.Options()` is tuned for mobile networks. Each rule can be switched off:

- **DNS** is answered by Xray over DNS-over-HTTPS through the proxy, so nothing leaks to the local resolver.
- **IPv6 is refused at once** (`blockIPv6`). Most proxy servers have no IPv6, so apps fall back to IPv4
  immediately instead of after a timeout, and IPv6 still can't bypass the tunnel.
- **QUIC is refused on VLESS** (`blockQUICOverTCP`). Browsers and video apps then use TCP, avoiding
  QUIC tunnelled inside TCP, which stalls. Hysteria2 is QUIC already, so it keeps UDP 443.
- **Private ranges go direct** (`bypassPrivateRanges`), spelled out so no `geoip.dat` is needed.

Customize in your extension:

```swift
final class PacketTunnelProvider: XrayPacketTunnelProvider {
    override var configOptions: XrayConfig.Options { .init(blockIPv6: false, logLevel: "info") }
}
```

Or override `makeConfig(for:)` to supply your own JSON (keep the `tun` inbound).

## Memory

iOS kills a packet-tunnel extension that uses more than about 50 MB. The bundled core caps Go's heap
at 32 MB with aggressive GC (see `scripts/build-xray.sh`).

## Building the core yourself

```sh
./scripts/build-xray.sh                  # needs Go and Xcode, writes Frameworks/Libv2ray.xcframework
VLESSKIT_LOCAL_CORE=1 swift build        # or open the package in Xcode with this variable set
```

## Tests

```sh
swift test                                                                      # parser and config, on macOS
VLESSKIT_LOCAL_CORE=1 xcodebuild test -scheme VLESSKit-Package -destination 'platform=iOS Simulator,name=iPhone 17'
```

## License

The Swift code is MIT. The bundled Xray core is LGPL-3.0 / MPL-2.0; see [NOTICE.md](NOTICE.md).
