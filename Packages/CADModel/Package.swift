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
        .library(name: "CADModelSolvers", targets: ["CADModelSolvers"]),
    ],
    dependencies: [
        .package(path: "../CADKernel"),
        .package(path: "../CADSolvers"),
    ],
    targets: [
        .target(name: "CADModel"),
        .target(
            name: "CADModelKernel",
            dependencies: ["CADModel", .product(name: "CADKernel", package: "CADKernel")]
        ),
        .target(
            name: "CADModelSolvers",
            dependencies: ["CADModel", .product(name: "CADSolvers", package: "CADSolvers")]
        ),
        .testTarget(name: "CADModelTests", dependencies: ["CADModel"]),
        .testTarget(name: "CADModelKernelTests", dependencies: ["CADModel", "CADModelKernel"]),
        .testTarget(name: "CADModelSolversTests", dependencies: ["CADModel", "CADModelKernel", "CADModelSolvers"]),
    ]
)
