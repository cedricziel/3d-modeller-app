// swift-tools-version: 5.9
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
    ]
)
