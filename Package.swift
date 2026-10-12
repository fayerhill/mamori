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
        .target(name: "MamoriGuardSupport", dependencies: ["MamoriCore"], path: "Sources/MamoriGuard", exclude: ["main.swift"]),
        .executableTarget(name: "MamoriGuard", dependencies: ["MamoriCore", "MamoriGuardSupport"], path: "Sources/MamoriGuard", exclude: ["GuardService.swift", "CommandRunner.swift", "JournalStore.swift", "GlobalProtectVerifier.swift", "PFRuleInspector.swift"], sources: ["main.swift"]),
        .testTarget(name: "MamoriCoreTests", dependencies: ["MamoriCore"]),
        .testTarget(name: "MamoriGuardTests", dependencies: ["MamoriCore", "MamoriGuardSupport"]),
        .testTarget(name: "MamoriSystemTests", dependencies: ["MamoriCore", "MamoriSystem"]),
        .testTarget(name: "MamoriAppTests", dependencies: ["Mamori", "MamoriSystem"])
    ]
)
