import Testing
@testable import OpenType

@Suite("Model upgrade policy")
struct ModelUpgradeTests {
    @Test("SeedASR 2.0 is the recommended Volcengine model")
    func recommendedVolcModel() {
        #expect(VolcASRModel.recommended == .seedASR2)
        #expect(VolcASRModel.recommended.rawValue == "volc.seedasr.sauc.duration")
    }
}
