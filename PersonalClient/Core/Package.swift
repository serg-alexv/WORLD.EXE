// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PersonalFeedCore",
    platforms: [.iOS("18.0"), .macOS(.v13)],
    products: [
        .library(name: "FeedDomain", targets: ["FeedDomain"]),
        .library(name: "FeedAdapters", targets: ["FeedAdapters"]),
        .library(name: "FeedStore", targets: ["FeedStore"])
    ],
    targets: [
        .target(name: "FeedDomain"),
        .target(name: "FeedAdapters", dependencies: ["FeedDomain"]),
        .target(name: "FeedStore", dependencies: ["FeedDomain"]),
        .testTarget(name: "FeedCoreTests", dependencies: ["FeedDomain", "FeedAdapters", "FeedStore"])
    ],
    swiftLanguageVersions: [.v5]
)
