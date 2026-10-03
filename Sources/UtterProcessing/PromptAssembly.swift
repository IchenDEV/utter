import UtterContracts
/// Splits an assembled LLM prompt into a byte-stable, cacheable instruction
/// prefix and the per-request context that follows it.
///
/// `stablePrefix` depends only on settings (language, style, format kind,
/// custom prompt, main vs command path) and is identical across requests.
/// `volatileContext` carries screen, memory, input-target, time, and personal
/// dictionary context; keeping it out of the prefix lets a prompt/KV cache key
/// on `(modelID, stablePrefix)` and lets provider-side prefix caching engage.
package struct PromptAssembly: Sendable, Equatable {
    package let stablePrefix: String
    package let volatileContext: String

    package init(stablePrefix: String, volatileContext: String = "") {
        self.stablePrefix = stablePrefix
        self.volatileContext = volatileContext
    }

    /// The legacy single-string system prompt: stable prefix then volatile
    /// context. Prefer passing `stablePrefix` as the system prompt and
    /// `userPrompt(containing:)` as the user turn for cacheable requests.
    package var systemPrompt: String {
        volatileContext.isEmpty ? stablePrefix : "\(stablePrefix)\n\n\(volatileContext)"
    }

    /// The user turn: volatile context (when present) ahead of the payload,
    /// preserving the original content order while keeping it out of the prefix.
    package func userPrompt(containing content: String) -> String {
        volatileContext.isEmpty ? content : "\(volatileContext)\n\n\(content)"
    }
}
