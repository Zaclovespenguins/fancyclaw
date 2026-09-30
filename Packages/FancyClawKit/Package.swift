// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FancyClawKit",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "GatewayProtocol", targets: ["GatewayProtocol"]),
        .library(name: "GatewayClient", targets: ["GatewayClient"]),
        .library(name: "ChatCore", targets: ["ChatCore"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "TestSupport", targets: ["TestSupport"]),
        .library(name: "SystemIntegration", targets: ["SystemIntegration"]),
        .library(name: "SystemActions", targets: ["SystemActions"]),
    ],
    dependencies: [
        // Pre-1.0: minor releases may break, so stay on 0.5.x.
        .package(url: "https://github.com/gonzalezreal/textual", .upToNextMinor(from: "0.5.0")),
    ],
    targets: [
        // Codable frames and models. Pure: no I/O.
        .target(name: "GatewayProtocol"),

        // WebSocket connection, device identity, Keychain, discovery.
        .target(name: "GatewayClient", dependencies: ["GatewayProtocol"]),

        // Observable stores that drive the UI.
        .target(name: "ChatCore", dependencies: ["GatewayProtocol", "GatewayClient", "Persistence"]),

        // SwiftData cache.
        .target(name: "Persistence", dependencies: ["GatewayProtocol"]),
        .target(name: "SystemIntegration", dependencies: ["SystemActions", "GatewayProtocol", "GatewayClient", "ChatCore", "Persistence"]),
        .target(name: "SystemActions"),

        // Tokens, glass components, Markdown styling.
        .target(
            name: "DesignSystem",
            dependencies: [.product(name: "Textual", package: "textual")]
        ),

        // FakeGateway, fixtures, and helpers shared by tests and UI-test launch modes.
        .target(
            name: "TestSupport",
            dependencies: ["GatewayProtocol", "GatewayClient"],
            resources: [.copy("Fixtures")]
        ),

        .testTarget(name: "GatewayProtocolTests", dependencies: ["GatewayProtocol", "TestSupport"]),
        .testTarget(name: "GatewayClientTests", dependencies: ["GatewayClient", "TestSupport"]),
        .testTarget(name: "ChatCoreTests", dependencies: ["ChatCore", "TestSupport"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence", "TestSupport"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        .testTarget(name: "TestSupportTests", dependencies: ["TestSupport"]),
        .testTarget(name: "SystemIntegrationTests", dependencies: ["SystemIntegration", "SystemActions", "TestSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
