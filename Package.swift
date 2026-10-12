// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mamori",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Mamori", targets: ["Mamori"]),
        .executable(name: "MamoriGuard", targets: ["MamoriGuard"]),
        .library(name: "MamoriCore", targets: ["MamoriCore"]),
        .library(name: "MamoriSystem", targets: ["MamoriSystem"])
    ],
    targets: [
        .target(name: "MamoriCore"),
        .target(name: "MamoriSystem", dependencies: ["MamoriCore"]),
        .executableTarget(name: "Mamori", dependencies: ["MamoriCore", "MamoriSystem"]),
        .executableTarget(name: "MamoriGuard", dependencies: ["MamoriCore"]),
        .testTarget(name: "MamoriCoreTests", dependencies: ["MamoriCore"])
    ]
)
