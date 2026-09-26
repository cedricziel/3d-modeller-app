// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CADKernel",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
    ],
    products: [
        .library(name: "CADKernel", targets: ["CADKernel"])
    ],
    dependencies: [
        .package(url: "https://github.com/SecondMouseAU/OCCTSwift.git", exact: "3.0.0")
    ],
    targets: [
        .target(
            name: "CADKernel",
            dependencies: [.product(name: "OCCTSwift", package: "OCCTSwift")]
        ),
        .testTarget(
            name: "CADKernelTests",
            dependencies: ["CADKernel"]
        ),
    ]
)
