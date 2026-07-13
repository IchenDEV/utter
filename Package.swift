// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenType",
    defaultLocalization: "en",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "OpenType", targets: ["OpenType"]),
        .executable(name: "OpenTypeCLI", targets: ["OpenTypeCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "OpenType",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ],
            path: "Sources",
            resources: [
                .copy("Resources/AppIcon.png"),
                .copy("Resources/AppIcon.icon"),
                .copy("Resources/AppIconDark.png"),
                .copy("Resources/AppIconLight.png"),
                .copy("Resources/Scripts"),
                .copy("Resources/Sounds"),
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/AppIconLight.icns"),
                .copy("Resources/AppIconDark.icns"),
                .process("Resources/en.lproj"),
                .process("Resources/zh-Hans.lproj"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "OpenTypeCLI",
            path: "SourcesCLI",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "OpenTypeTests",
            dependencies: ["OpenType"],
            path: "Tests/OpenTypeTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
