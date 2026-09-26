// swift-tools-version: 6.1
import PackageDescription

let planeGCSSettings: [CXXSetting] = [
    .define("NDEBUG"),
    .define("EIGEN_NO_DEBUG"),
    .define("EIGEN_MPL2_ONLY"),
    .define("_LIBCPP_DISABLE_DEPRECATION_WARNINGS"),
]

let package = Package(
    name: "CADSolvers",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
    ],
    products: [
        .library(name: "CADSolvers", targets: ["CADSolvers"])
    ],
    targets: [
        .target(
            name: "PlaneGCS",
            exclude: ["VENDORED.md", "LICENSES"],
            publicHeadersPath: "include",
            cxxSettings: planeGCSSettings
        ),
        .target(name: "CPlaneGCS", dependencies: ["PlaneGCS"], cxxSettings: planeGCSSettings),
        .target(name: "CADSolvers", dependencies: ["CPlaneGCS"]),
    ],
    cxxLanguageStandard: .cxx2b
)
