// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WorldCore",
    platforms: [.iOS("18.0"), .macOS(.v13)],
    products: [.library(name: "WorldCore", targets: ["WorldCore"]), .library(name: "EvidenceCore", targets: ["EvidenceCore"])],
    targets: [
        .target(name: "WorldCore"),
        .target(name: "EvidenceCore"),
        .testTarget(name: "EvidenceCoreTests", dependencies: ["EvidenceCore"]),
        .testTarget(name: "WorldCoreTests", dependencies: ["WorldCore"])
    ],
    swiftLanguageVersions: [.v5]
)
