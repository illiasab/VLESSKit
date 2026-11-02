# VLESSKit

A Swift package for building VLESS, Shadowsocks and Hysteria2 VPN apps on iOS with
[Xray-core](https://github.com/XTLS/Xray-core) running inside a Network Extension.

- **`VLESSKit`**: share-link parsing and Xray config generation. Pure Swift, iOS and macOS, no binary.
- **`VLESSKitTunnel`**: a ready `NEPacketTunnelProvider` that runs Xray in-process on the utun file
  descriptor (no tun2socks), plus `VLESSTunnelManager` to install and start the VPN from your app.

## Supported links

| Scheme | Transports and options |
|---|---|
| `vless://` | `tcp`/`raw` (incl. HTTP header), `ws`, `httpupgrade`, `grpc`, `xhttp` (with `extra` JSON); `none`, `tls`, `reality`; `flow`, `fp`, `alpn`, `sni`, `fragment` |
| `ss://` | SIP002 and legacy base64 |
| `hysteria2://`, `hy2://` | `sni`, `insecure`, salamander `obfs`, port hopping (`mport`) |

## Install

```swift
.package(url: "https://github.com/illiasab/VLESSKit.git", from: "0.1.0")
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

**Config only**, e.g. to run Xray yourself:

```swift
import VLESSKit

let link = ShareLink("hy2://auth@example.com:443?obfs=salamander&obfs-password=pw")!
let json = try XrayConfig.jsonString(link)
```

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
