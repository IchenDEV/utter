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

#if os(macOS)
let dataExclusions: [String] = []
let builtinDependencies: [Target.Dependency] = ["UtterMediaContracts", "UtterModels", "UtterSession", "UtterProcessing",
    "UtterAudio", "UtterMacServices", "UtterRemoteMic", "UtterAppleSpeech", "UtterWhisper", "UtterMLX", "UtterANE", "UtterRemoteInference", "UtterIngress", "UtterPresentation"]
let builtinExclusions: [String] = []
let modelDependencies: [Target.Dependency] = [
    "UtterMediaContracts", "UtterPresentationContracts",
    .product(name: "WhisperKit", package: "argmax-oss-swift"),
    .product(name: "Hub", package: "swift-transformers"),
]
let modelExclusions: [String] = []
let remoteDependencies: [Target.Dependency] = ["UtterMediaContracts"]
let remoteExclusions: [String] = []
let sessionDependencies: [Target.Dependency] = ["UtterMediaContracts"]
let sessionExclusions: [String] = []
let processingDependencies: [Target.Dependency] = ["UtterMediaContracts"]
let processingExclusions: [String] = []
let audioDependencies: [Target.Dependency] = ["UtterMediaContracts"]
let audioExclusions: [String] = []
let remoteMicDependencies: [Target.Dependency] = ["UtterMediaContracts"]
let remoteMicExclusions: [String] = []
let macServiceDependencies: [Target.Dependency] = ["UtterMediaContracts"]
let macServiceExclusions: [String] = []
let ingressDependencies: [Target.Dependency] = ["UtterMediaContracts", "UtterPresentationContracts"]
let ingressExclusions: [String] = []
#else
let dataExclusions = ["SystemDiagnostics.swift"]
let builtinDependencies: [Target.Dependency] = []
let builtinExclusions = ["Native"]
let modelDependencies: [Target.Dependency] = []
let modelExclusions = ["SpeechRegistry.swift", "ImageRegistry.swift", "Native"]
let sessionDependencies: [Target.Dependency] = []
let sessionExclusions = ["Native"]
let processingDependencies: [Target.Dependency] = []
let processingExclusions = ["Native"]
let audioDependencies: [Target.Dependency] = []
let audioExclusions = ["Native"]
let remoteMicDependencies: [Target.Dependency] = []
let remoteMicExclusions = ["Native"]
let macServiceDependencies: [Target.Dependency] = []
let macServiceExclusions = ["Native"]
let ingressDependencies: [Target.Dependency] = []
let ingressExclusions = ["Native"]
let remoteDependencies: [Target.Dependency] = []
let remoteExclusions = ["GzipCompression.swift", "VolcSpeechEngine+Audio.swift", "VolcSpeechEngine+Codec.swift", "VolcSpeechEngine+Requests.swift", "VolcSpeechEngine+Transport.swift", "VolcSpeechEngine.swift", "VolcSpeechPlugins.swift", "VolcStreamingSession.swift"]
#endif

let portableTargets: [Target] = [
    .target(name: "UtterIngress", dependencies: ["UtterRuntime", "UtterContracts"] + ingressDependencies,
        exclude: ingressExclusions, swiftSettings: [.swiftLanguageMode(.v5)]),
    .testTarget(name: "UtterIngressTests", dependencies: ["UtterIngress", "UtterSession", "UtterData"],
        swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(name: "UtterBuiltins", dependencies: ["UtterRuntime", "UtterContracts", "UtterData"] + builtinDependencies,
        exclude: builtinExclusions, swiftSettings: [.swiftLanguageMode(.v5)]),
    .testTarget(name: "UtterBuiltinsTests", dependencies: ["UtterBuiltins", "UtterRuntime"],
        swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(name: "UtterEvaluation", dependencies: ["UtterContracts"], swiftSettings: [.swiftLanguageMode(.v5)]),
    .testTarget(name: "UtterEvaluationTests", dependencies: ["UtterEvaluation"], swiftSettings: [.swiftLanguageMode(.v5)]),
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
        exclude: dataExclusions,
        resources: [.copy("Resources/IndustryLexicons.json"), .copy("Resources/THUOCL-LICENSE.txt")],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
        name: "UtterMacServices", dependencies: ["UtterRuntime", "UtterContracts"] + macServiceDependencies,
        exclude: macServiceExclusions, resources: [.copy("Resources/Sounds")],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
        name: "UtterMacServicesTests", dependencies: ["UtterMacServices", "UtterContracts", "UtterRuntime", "UtterData"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
        name: "UtterRemoteMic", dependencies: ["UtterRuntime", "UtterContracts"] + remoteMicDependencies,
        exclude: remoteMicExclusions,
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
        name: "UtterRemoteMicTests", dependencies: ["UtterRemoteMic", "UtterContracts", "UtterRuntime"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
        name: "UtterAudio", dependencies: ["UtterRuntime", "UtterContracts"] + audioDependencies,
        exclude: audioExclusions, swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
        name: "UtterAudioTests", dependencies: ["UtterAudio", "UtterContracts", "UtterRuntime"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
        name: "UtterProcessing",
        dependencies: ["UtterRuntime", "UtterContracts"] + processingDependencies,
        exclude: processingExclusions,
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
        name: "UtterProcessingTests",
        dependencies: ["UtterProcessing", "UtterContracts", "UtterRemoteInference"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
        name: "UtterRemoteInference",
        dependencies: ["UtterRuntime", "UtterContracts"] + remoteDependencies,
        exclude: remoteExclusions,
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
        name: "UtterModels",
        dependencies: ["UtterRuntime", "UtterContracts"] + modelDependencies,
        exclude: modelExclusions,
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
        name: "UtterSession",
        dependencies: ["UtterRuntime", "UtterContracts"] + sessionDependencies,
        exclude: sessionExclusions,
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
        dependencies: ["UtterContracts", "UtterRuntime"],
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
        name: "UtterRemoteInferenceTests",
        dependencies: ["UtterRemoteInference", "UtterContracts", "UtterRuntime", "UtterModels"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
        name: "UtterModelsTests",
        dependencies: ["UtterModels", "UtterContracts", "UtterRuntime"],
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
        .macOS("26.0"), .iOS("27.0")
    ],
    products: [
        .executable(name: "OpenType", targets: ["OpenType"]),
        .executable(name: "OpenTypeCLI", targets: ["OpenTypeCLI"]),
        .executable(name: "UtterVoiceEval", targets: ["UtterVoiceEval"]),
        .library(name: "UtterMobile", targets: ["UtterMobile"]),
        .library(name: "UtterKeyboardBridge", targets: ["UtterKeyboardBridge"]),
    ],
    dependencies: dependencies,
    targets: [
        .executableTarget(name: "UtterVoiceEval",
            dependencies: ["UtterEvaluation", "UtterRuntime", "UtterContracts", "UtterData", "UtterModels",
                           "UtterMediaContracts", "UtterProcessing", "UtterMLX", "UtterWhisper", "UtterAudio"],
            path: "scripts/evaluate-voice", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "UtterKeyboardBridge", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "UtterMobile", dependencies: ["UtterKeyboardBridge", "UtterRuntime", "UtterContracts", "UtterData", "UtterProcessing", "UtterSession", "UtterMediaContracts", "UtterAppleSpeech", "UtterModels", "UtterWhisper", "UtterMLX"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "UtterWhisper",
            dependencies: [
                "UtterRuntime", "UtterContracts", "UtterMediaContracts",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "UtterMLX",
            dependencies: [
                "UtterRuntime", "UtterContracts", "UtterMediaContracts",
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "UtterANE",
            dependencies: [
                "UtterRuntime", "UtterContracts",
                .product(name: "ANELMRuntime", package: "ANE-LM"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "UtterAppleSpeech",
            dependencies: ["UtterRuntime", "UtterContracts", "UtterMediaContracts"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "UtterMediaContracts",
            dependencies: ["UtterRuntime", "UtterContracts"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "UtterPresentationContracts",
            dependencies: ["UtterRuntime", "UtterContracts", "UtterMediaContracts"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(name: "UtterPresentation",
            dependencies: ["UtterRuntime", "UtterContracts", "UtterMediaContracts", "UtterPresentationContracts"],
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
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/AppIconLight.icns"),
                .copy("Resources/AppIconDark.icns"),
            ], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "OpenType",
            dependencies: ["UtterBuiltins", "UtterContracts"],
            path: "Sources/App", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "OpenTypeCLI",
            path: "SourcesCLI",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "OpenTypeTests",
            dependencies: ["OpenType", "UtterPresentation", "UtterIngress", "UtterBuiltins", "UtterMacServices", "UtterRemoteMic", "UtterAudio", "UtterContracts", "UtterRuntime", "UtterData", "UtterSession", "UtterModels", "UtterAppleSpeech", "UtterWhisper", "UtterMLX", "UtterANE", "UtterRemoteInference", "UtterProcessing", "UtterMediaContracts", "UtterPresentationContracts"],
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
