// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftUIAssistant",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
        .visionOS("26.0")
    ],
    products: [
        .library(name: "SwiftUIAssistant", targets: ["SwiftUIAssistant"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SwiftUIAssistant",
            dependencies: [],
            path: "Sources/SwiftUIAssistant"
        ),
        .testTarget(
            name: "SwiftUIAssistantTests",
            dependencies: ["SwiftUIAssistant"],
            path: "Tests/SwiftUIAssistantTests"
        ),
    ]
)
