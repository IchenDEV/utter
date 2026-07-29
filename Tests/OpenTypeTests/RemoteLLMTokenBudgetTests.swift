import XCTest
@testable import OpenType

final class RemoteLLMTokenBudgetTests: XCTestCase {
    func testRetriesLargeTokenLimitFailuresAtCompatibleBudget() {
        XCTAssertEqual(
            RemoteLLMClient.retryTokenBudget(
                maxTokens: 4_096,
                failureMessage: "HTTP 400: maximum context length exceeded"
            ),
            1_024
        )
        XCTAssertEqual(
            RemoteLLMClient.retryTokenBudget(
                maxTokens: 640,
                failureMessage: "max_tokens must be less than the token limit"
            ),
            320
        )
    }

    func testDoesNotRetryAuthenticationOrAlreadySmallBudgets() {
        XCTAssertNil(RemoteLLMClient.retryTokenBudget(
            maxTokens: 4_096,
            failureMessage: "HTTP 401: invalid API key"
        ))
        XCTAssertNil(RemoteLLMClient.retryTokenBudget(
            maxTokens: 256,
            failureMessage: "context_length exceeded"
        ))
        XCTAssertNil(RemoteLLMClient.retryTokenBudget(
            maxTokens: 4_096,
            failureMessage: "HTTP 400: unsupported parameter max_tokens; use max_completion_tokens"
        ))
        XCTAssertNil(RemoteLLMClient.retryTokenBudget(
            maxTokens: 4_096,
            failureMessage: "HTTP 429: account token limit reached"
        ))
    }

    func testRejectsProviderTruncatedResponses() throws {
        let openAI = Data(
            #"{"choices":[{"finish_reason":"length","message":{"content":"partial"}}]}"#
                .utf8
        )
        let anthropic = Data(
            #"{"stop_reason":"max_tokens","content":[{"type":"text","text":"partial"}]}"#
                .utf8
        )

        XCTAssertThrowsError(try RemoteLLMResponseText.openAI(from: openAI))
        XCTAssertThrowsError(try RemoteLLMResponseText.anthropic(from: anthropic))
    }
}
