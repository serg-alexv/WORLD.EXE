// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "LocalLlama",
    platforms: [.iOS("18.0"), .macOS("13.3")],
    products: [.library(name: "LocalLlama", targets: ["LlamaBridge"]),
               .executable(name: "LlamaSmoke", targets: ["LlamaSmoke"])],
    targets: [
        .binaryTarget(name: "llama", path: "Frameworks/llama.xcframework"),
        .target(name: "LlamaBridge", dependencies: ["llama"], publicHeadersPath: "include",
                linkerSettings: [.linkedLibrary("c++"), .linkedFramework("Accelerate"),
                                  .linkedFramework("Metal"), .linkedFramework("Foundation")]),
        .executableTarget(name: "LlamaSmoke", dependencies: ["LlamaBridge"])
    ],
    cxxLanguageStandard: .cxx17
)
