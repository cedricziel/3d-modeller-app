// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CADAssistantTools",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
    ],
    products: [
        .library(name: "CADAssistantTools", targets: ["CADAssistantTools"]),
        .library(name: "CADBench", targets: ["CADBench"]),
        .executable(name: "cadbench", targets: ["CADBenchCLI"]),
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
        .target(
            name: "CADBench",
            dependencies: [
                "CADAssistantTools",
                .product(name: "SwiftUIAssistant", package: "SwiftUIAssistant"),
                .product(name: "CADModel", package: "CADModel"),
            ]
        ),
        .executableTarget(
            name: "CADBenchCLI",
            dependencies: [
                "CADBench",
                .product(name: "SwiftUIAssistant", package: "SwiftUIAssistant"),
                .product(name: "CADModel", package: "CADModel"),
                .product(name: "CADModelKernel", package: "CADModel"),
                .product(name: "CADModelSolvers", package: "CADModel"),
            ],
            path: "Sources/CADBenchCLI"
        ),
        .testTarget(
            name: "CADAssistantToolsTests",
            dependencies: [
                "CADAssistantTools",
                .product(name: "SwiftUIAssistant", package: "SwiftUIAssistant"),
                .product(name: "CADModel", package: "CADModel"),
                .product(name: "CADModelKernel", package: "CADModel"),
                .product(name: "CADModelSolvers", package: "CADModel"),
            ]
        ),
        .testTarget(
            name: "CADBenchTests",
            dependencies: [
                "CADBench",
                "CADAssistantTools",
                .product(name: "SwiftUIAssistant", package: "SwiftUIAssistant"),
                .product(name: "CADModel", package: "CADModel"),
                .product(name: "CADModelKernel", package: "CADModel"),
                .product(name: "CADModelSolvers", package: "CADModel"),
            ]
        ),
    ]
)
