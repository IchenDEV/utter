import UtterMediaContracts
import UtterPresentationContracts
import UtterData
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterANE
import UtterRemoteInference
import UtterIngress
import XCTest
import MLXLMCommon
import UtterContracts
import UtterModels
@testable import UtterMLX

final class LocalGenerationLoadingTests: XCTestCase {
    func testGemmaEOSConfigurationResolvesOnlyLocalModelAndTokenizerPaths() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"model_type":"gemma4"}"#.utf8).write(to: directory.appendingPathComponent("config.json"))
        let configuration = try MLXModelLoading.configuration(id: "local/custom-model", directory: directory)
        XCTAssertEqual(configuration.extraEOSTokens, ["<turn|>"])
        XCTAssertEqual(configuration.effectiveStopStrings, ["<turn|>"])
        let resolved = try await resolve(configuration: configuration, from: MLXModelLoading.offlineDownloader,
            useLatest: false, progressHandler: { _ in })
        XCTAssertEqual(resolved.modelDirectory, directory)
        XCTAssertEqual(resolved.tokenizerDirectory, directory)
        XCTAssertEqual(resolved.extraEOSTokens, ["<turn|>"])
        do {
            _ = try await MLXModelLoading.offlineDownloader.download(id: "implicit/hub", revision: nil,
                matching: ["*"], useLatest: false, progressHandler: { _ in })
            XCTFail("Inference downloader admitted a Hub request")
        } catch GenerationServiceError.modelUnavailable {}
    }

    func testLargeMixtureModelsCannotBeRecommendedOnSmallMachines() throws {
        let scout = "mlx-community/Llama-4-Scout-17B-16E-Instruct-4bit"
        let maverick = "mlx-community/Llama-4-Maverick-17B-128E-Instruct-4bit"
        let artifact = try XCTUnwrap(MLXModelArtifacts.text.first { $0.id == scout })
        for memory in [8.0, 16, 24, 32, 48, 64] {
            XCTAssertEqual(DeviceCapability.tier(for: artifact, memoryGB: memory), .standard)
        }
        XCTAssertEqual(DeviceCapability.tier(for: artifact, memoryGB: 96), .recommended)
        XCTAssertEqual(try XCTUnwrap(MLXModelArtifacts.text.first { $0.id == maverick }).memoryRequirements?.minimumGB, 256)
    }
}
