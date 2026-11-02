// swift-tools-version:5.9
import PackageDescription

// Set VLESSKIT_LOCAL_CORE=1 to use Frameworks/Libv2ray.xcframework built by scripts/build-xray.sh
// instead of the prebuilt one attached to the GitHub release.
let localCore = Context.environment["VLESSKIT_LOCAL_CORE"] == "1"

let core: Target = localCore
    ? .binaryTarget(name: "Libv2ray", path: "Frameworks/Libv2ray.xcframework")
    : .binaryTarget(
        name: "Libv2ray",
        url: "https://github.com/illiasab/VLESSKit/releases/download/0.1.0/Libv2ray.xcframework.zip",
        checksum: "25f6e50f80218f87fd6a3783c62264ddcb31468234acb966fec4ccbd6e103519"
    )

let package = Package(
    name: "VLESSKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        // Share-link parsing and Xray config generation. Pure Swift, no binary.
        .library(name: "VLESSKit", targets: ["VLESSKit"]),
        // A ready NEPacketTunnelProvider running Xray-core in-process. iOS only.
        .library(name: "VLESSKitTunnel", targets: ["VLESSKitTunnel"]),
    ],
    targets: [
        .target(name: "VLESSKit"),
        .target(
            name: "VLESSKitTunnel",
            dependencies: [
                "VLESSKit",
                .target(name: "Libv2ray", condition: .when(platforms: [.iOS])),
            ],
            // Xray's Go runtime resolves DNS through libresolv.
            linkerSettings: [.linkedLibrary("resolv", .when(platforms: [.iOS]))]
        ),
        core,
        .testTarget(name: "VLESSKitTests", dependencies: ["VLESSKit"]),
        .testTarget(name: "VLESSKitTunnelTests", dependencies: ["VLESSKitTunnel"]),
    ]
)
