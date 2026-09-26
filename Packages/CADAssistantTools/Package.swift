// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CADAssistantTools",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
    ],
    products: [
        .library(name: "CADAssistantTools", targets: ["CADAssistantTools"])
    ],
    dependencies: [
        .package(path: "../SwiftUIAssistant"),
        .package(path: "../CADModel"),
    ],
    targets: [
        .target(
            name: "CADAssistantTools",
            dependencies: [
                .product(name: "SwiftUIAssistant", package: "SwiftUIAssistant"),
                .product(name: "CADModel", package: "CADModel"),
            ]
        ),
        .testTarget(
            name: "CADAssistantToolsTests",
            dependencies: [
                "CADAssistantTools",
                .product(name: "SwiftUIAssistant", package: "SwiftUIAssistant"),
                .product(name: "CADModel", package: "CADModel"),
                .product(name: "CADModelKernel", package: "CADModel"),
            ]
        ),
    ]
)
