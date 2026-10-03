// swift-tools-version: 6.2
import PackageDescription

let dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
    .package(
        url: "https://github.com/IchenDEV/ANE-LM.git",
        revision: "033472ec12ea796fc7ea4f8cefd7ed456f69900b"
    ),
    .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", exact: "0.1.3"),
    .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.3"),
    .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.31.4"),
]

let portableTargets: [Target] = [
    .target(name: "UtterRuntime", swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(
        name: "UtterContracts",
        dependencies: ["UtterRuntime"],
        resources: [.process("Resources/en.lproj"), .process("Resources/zh-Hans.lproj")],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
        name: "UtterData",
        dependencies: ["UtterRuntime", "UtterContracts"],
        resources: [.copy("Resources/IndustryLexicons.json"), .copy("Resources/THUOCL-LICENSE.txt")],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
        name: "UtterSession",
        dependencies: ["UtterRuntime", "UtterContracts"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .executableTarget(
        name: "UtterLexiconCheck",
        dependencies: ["UtterData", "UtterContracts"],
        path: "scripts/tests/industry-lexicon",
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
        name: "UtterContractsTests",
        dependencies: ["UtterContracts"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
        name: "UtterDataTests",
        dependencies: ["UtterData", "UtterContracts", "UtterRuntime"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
        name: "UtterRuntimeTests",
        dependencies: ["UtterRuntime"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
        name: "UtterSessionTests",
        dependencies: ["UtterSession", "UtterContracts", "UtterData"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
]

#if os(macOS)
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
    dependencies: dependencies,
    targets: [
        .executableTarget(
            name: "OpenType",
            dependencies: [
                "UtterRuntime",
                "UtterContracts",
                "UtterData",
                "UtterSession",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "ANELMRuntime", package: "ANE-LM"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ],
            path: "Sources",
            exclude: ["UtterRuntime", "UtterContracts", "UtterData", "UtterSession"],
            resources: [
                .copy("Resources/AppIcon.png"),
                .copy("Resources/AppIcon.icon"),
                .copy("Resources/AppIconDark.png"),
                .copy("Resources/AppIconLight.png"),
                .copy("Resources/SettingsActivityIllustration.png"),
                .copy("Resources/SettingsVoiceIllustration.png"),
                .copy("Resources/SettingsModelsIllustration.png"),
                .copy("Resources/SettingsStyleIllustration.png"),
                .copy("Resources/SettingsIntegrationsIllustration.png"),
                .copy("Resources/SettingsAboutIllustration.png"),
                .copy("Resources/Sounds"),
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/AppIconLight.icns"),
                .copy("Resources/AppIconDark.icns"),
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
            dependencies: ["OpenType", "UtterContracts", "UtterRuntime", "UtterData", "UtterSession"],
            path: "Tests/OpenTypeTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ] + portableTargets
)
#else
// Linux tests the actual Foundation-only modules; the macOS app requires its SDK.
let package = Package(name: "OpenType", defaultLocalization: "en", dependencies: dependencies, targets: portableTargets)
#endif
