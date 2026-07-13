import Testing
@testable import OpenType

@Suite("Model upgrade policy")
struct ModelUpgradeTests {
    @Test("Qwen runtime marker includes the pinned version")
    func qwenRuntimeMarkerVersion() {
        #expect(LocalASRRuntime.qwenRequirement == "qwen3-asr-mlx==0.1.1")
        #expect(LocalASRRuntime.qwenMarkerIsCurrent("qwen3-asr-mlx==0.1.1"))
        #expect(!LocalASRRuntime.qwenMarkerIsCurrent("qwen3-asr-mlx"))
        #expect(!LocalASRRuntime.qwenMarkerIsCurrent("qwen3-asr-mlx==0.1.0"))
    }

    @Test("SeedASR 2.0 is the recommended Volcengine model")
    func recommendedVolcModel() {
        #expect(VolcASRModel.recommended == .seedASR2)
        #expect(VolcASRModel.recommended.rawValue == "volc.seedasr.sauc.duration")
    }
}
