import XCTest
import Tokenizers
@testable import OpenType

/// Verifies what the Swift tokenizer stack actually renders for Qwen3.5's chat
/// template (thinking block on/off), using the locally downloaded model.
final class ChatTemplateProbe: XCTestCase {
    func testRenderQwen35Template() async throws {
        guard ProcessInfo.processInfo.environment["OPENTYPE_TEMPLATE_PROBE"] == "1" else {
            throw XCTSkip("Set OPENTYPE_TEMPLATE_PROBE=1 to run")
        }
        let modelDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenType/huggingface/models/mlx-community/Qwen3.5-2B-4bit")
        guard FileManager.default.fileExists(atPath: modelDir.path) else {
            throw XCTSkip("Qwen3.5-2B-4bit not downloaded")
        }

        let tokenizer = try await AutoTokenizer.from(modelFolder: modelDir)
        let messages: [[String: any Sendable]] = [
            ["role": "system", "content": "S"],
            ["role": "user", "content": "U"],
        ]
        let ids = try tokenizer.applyChatTemplate(messages: messages)
        let rendered = tokenizer.decode(tokens: ids, skipSpecialTokens: false)
        print("TEMPLATE_PROBE default => \(rendered.replacingOccurrences(of: "\n", with: "⏎"))")

        let idsNoThink = try tokenizer.applyChatTemplate(
            messages: messages,
            tools: nil,
            additionalContext: ["enable_thinking": false]
        )
        let renderedNoThink = tokenizer.decode(tokens: idsNoThink, skipSpecialTokens: false)
        print("TEMPLATE_PROBE enable_thinking=false => \(renderedNoThink.replacingOccurrences(of: "\n", with: "⏎"))")
    }
}
