// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftUIAssistantTools",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
        .visionOS("26.0")
    ],
    products: [
        .library(name: "SwiftUIAssistantTools", targets: ["SwiftUIAssistantTools"]),
    ],
    dependencies: [
        .package(path: "../SwiftUIAssistant")
    ],
    targets: [
        .target(
            name: "SwiftUIAssistantTools",
            dependencies: ["SwiftUIAssistant"],
            path: "Sources/SwiftUIAssistantTools"
        ),
        .testTarget(
            name: "SwiftUIAssistantToolsTests",
            dependencies: ["SwiftUIAssistantTools"],
            path: "Tests/SwiftUIAssistantToolsTests"
        ),
    ]
)
