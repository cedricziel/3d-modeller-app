// swift-tools-version: 6.1
import PackageDescription

let planeGCSSettings: [CXXSetting] = [
    .define("NDEBUG"),
    .define("EIGEN_NO_DEBUG"),
    .define("EIGEN_MPL2_ONLY"),
    .define("_LIBCPP_DISABLE_DEPRECATION_WARNINGS"),
]

/// OndselSolver files that compile through `NarrowingWrappers.cpp`; see `Sources/OndselSolver/VENDORED.md`.
let ondselWrapped = [
    "AbsConstraint.cpp", "AtPointConstraintIqcJqc.cpp", "DirectionCosineConstraintIqcJqc.cpp",
    "TranslationConstraintIqcJqc.cpp", "SymbolicParser.cpp",
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
        .target(
            name: "OndselSolver",
            exclude: ["VENDORED.md", "LICENSES"] + ondselWrapped.map { "include/OndselSolver/\($0)" },
            publicHeadersPath: "include",
            cxxSettings: [.define("NDEBUG")]
        ),
        .target(name: "COndselSolver", dependencies: ["OndselSolver"], cxxSettings: [.define("NDEBUG")]),
        .target(name: "CADSolvers", dependencies: ["CPlaneGCS", "COndselSolver"]),
        .testTarget(name: "CADSolversTests", dependencies: ["CADSolvers"]),
    ],
    cxxLanguageStandard: .cxx2b
)
