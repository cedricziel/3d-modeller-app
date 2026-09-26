// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CADModel",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
    ],
    products: [
        .library(name: "CADModel", targets: ["CADModel"]),
        .library(name: "CADModelKernel", targets: ["CADModelKernel"]),
    ],
    dependencies: [
        .package(path: "../CADKernel")
    ],
    targets: [
        .target(name: "CADModel"),
        .target(
            name: "CADModelKernel",
            dependencies: ["CADModel", .product(name: "CADKernel", package: "CADKernel")]
        ),
        .testTarget(name: "CADModelTests", dependencies: ["CADModel"]),
        .testTarget(name: "CADModelKernelTests", dependencies: ["CADModel", "CADModelKernel"]),
    ]
)
