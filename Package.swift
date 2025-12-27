// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "3DModellerApp",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
        .visionOS("26.0")
    ],
    products: [
        .executable(
            name: "3DModellerApp",
            targets: ["3DModellerApp"]
        )
    ],
    dependencies: [
        .package(path: "Packages/SwiftUIAssistant")
    ],
    targets: [
        .executableTarget(
            name: "3DModellerApp",
            dependencies: ["SwiftUIAssistant"],
            path: "3DModellerApp"
        )
    ]
)
