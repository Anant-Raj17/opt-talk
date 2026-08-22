// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "opt-talk",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OptTalk", targets: ["OptTalk"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
        .package(url: "https://github.com/mattt/llama.swift", from: "2.10549.0"),
    ],
    targets: [
        .target(
            name: "S1Mini",
            dependencies: [
                .product(name: "LlamaSwift", package: "llama.swift")
            ],
            path: "Sources/S1Mini",
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
        .executableTarget(
            name: "OptTalk",
            dependencies: [
                "S1Mini",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/OptTalk",
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
    ]
)
