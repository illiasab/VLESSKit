# Third-party components

The MIT license in `LICENSE` covers the Swift sources in this repository only.

`Libv2ray.xcframework`, attached to each GitHub release and fetched by Swift Package Manager, is a
compiled build of third-party code under its own licenses:

| Component | License | Source |
|---|---|---|
| AndroidLibXrayLite (the `Libv2ray` wrapper) | LGPL-3.0 | https://github.com/2dust/AndroidLibXrayLite |
| Xray-core | MPL-2.0 | https://github.com/XTLS/Xray-core |
| Go runtime and golang.org/x/mobile | BSD-3-Clause | https://go.dev |

The exact upstream release and commit are pinned in `scripts/build-xray.sh`, which rebuilds the
framework from source. The framework is linked statically, so to meet LGPL-3.0 an app that ships it
should let users relink it with a modified version: point them to this script and to the
`VLESSKIT_LOCAL_CORE=1` switch in `Package.swift`.
