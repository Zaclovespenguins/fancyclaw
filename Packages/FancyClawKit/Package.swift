// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FancyClawKit",
    platforms: [
        .iOS(.v26),
        // macOS is listed only so the pure-logic modules can run `swift test` on the host.
        .macOS(.v26),
    ],
    products: [
        .library(name: "GatewayProtocol", targets: ["GatewayProtocol"]),
        .library(name: "TestSupport", targets: ["TestSupport"]),
    ],
    targets: [
        .target(name: "GatewayProtocol"),
        .target(
            name: "TestSupport",
            dependencies: ["GatewayProtocol"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "GatewayProtocolTests",
            dependencies: ["GatewayProtocol", "TestSupport"]
        ),
    ]
)
