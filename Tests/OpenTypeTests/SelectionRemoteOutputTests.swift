import Foundation
import XCTest
import UtterContracts
import UtterMediaContracts
import UtterProcessing
import UtterRemoteInference
import UtterRuntime
import UtterSession

@MainActor
final class SelectionRemoteOutputTests: XCTestCase {
    private let invalid = [
        #"{"final_text":"","text":"Deleted.","reason":"delete_selection"}"#,
        #"{"action":"delete_selection","text":"Deleted.","confidence":1}"#,
        #"{"final_text":{"final_text":"","text":"Deleted.","reason":"delete_selection"}}"#,
        #"{"final_text":{"action":"delete_selection","text":"Deleted.","confidence":1}}"#,
    ]

    func testNativeGeneratorRejectsMetadataThroughBothRemoteAPIsAndEveryEnvelope() async throws {
        for provider in [RemoteProvider.custom, .claude] {
            for payload in invalid {
                for shape in ["text", "contentObject", "parsed", "tool", "parsedTool", "toolFallback", "json", "jsonFallback", "typedEmptyFinal", "typedFallback", "stream", "toolStream"] {
                    let fixture = SelectionRemoteOutputFixture(provider: provider, body: try response(payload, provider, shape))
                    let candidate = await fixture.processor.processSelectionEdit(selectedText: "Original 👩🏽‍💻",
                        intent: .custom("rewrite politely"), options: fixture.options)
                    XCTAssertEqual(candidate, "", "\(provider) \(shape): \(payload)")
                    XCTAssertEqual(fixture.requests.count, 1)
                    XCTAssertTrue(fixture.requests.first?.url?.path.hasSuffix(provider == .claude ? "/messages" : "/chat/completions") == true)
                    await fixture.close()
                }
            }
        }
    }

    func testNativeGeneratorKeepsPlainAndExplicitFinalsWithoutChangingOrdinaryRequests() async throws {
        let valid = ["Please send the notes. 👩🏽‍💻", #"{"final_text":"Please send the notes. 👩🏽‍💻"}"#,
            #"{"data":"{\"final_text\":\"Please send the notes. 👩🏽‍💻\"}"}"#,
            #"{"type":"final_text","content":{"value":"Please send the notes. 👩🏽‍💻"}}"#]
        for provider in [RemoteProvider.custom, .claude] {
            for payload in valid {
              for shape in payload.hasPrefix("{") ? ["text", "contentObject", "parsed", "tool", "parsedTool", "json", "typedFallback", "stream", "toolStream"] : ["text", "typedFallback", "stream"] {
                let fixture = SelectionRemoteOutputFixture(provider: provider, body: try response(payload, provider, shape))
                let candidate = await fixture.processor.processSelectionEdit(selectedText: "Original 👩🏽‍💻",
                    intent: .custom("rewrite politely"), options: fixture.options)
                XCTAssertEqual(candidate, "Please send the notes. 👩🏽‍💻", "\(provider) \(shape): \(payload)")
                await fixture.close()
              }
            }
            let fixture = SelectionRemoteOutputFixture(provider: provider, body: try response(invalid[0], provider, "text"))
            let ordinary = try await fixture.client.generate(TextGenerationRequest(prompt: "ordinary", modelID: "fixture-model",
                remote: .init(baseURL: fixture.options.remoteBaseURL, apiKey: "synthetic-token", provider: provider)))
            XCTAssertEqual(ordinary, "Deleted.")
            await fixture.close()
            for payload in invalid.dropFirst(2) {
                let ordinaryFixture = SelectionRemoteOutputFixture(provider: provider, body: try response(payload, provider, "text"))
                let ordinary = try await ordinaryFixture.client.generate(TextGenerationRequest(prompt: "ordinary", modelID: "fixture-model",
                    remote: .init(baseURL: ordinaryFixture.options.remoteBaseURL, apiKey: "synthetic-token", provider: provider)))
                XCTAssertEqual(ordinary, "Deleted.")
                await ordinaryFixture.close()
            }
        }
    }

    func testStrictRemoteExtractionKeepsTypedStructureBeforeTheFinalParser() throws {
        for provider in [RemoteProvider.custom, .claude] {
            for payload in invalid + [#"{"final_text":"Keep the notes."}"#] {
                let body = try response(payload, provider, "typedFallback")
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
                let raw = try XCTUnwrap(LLMFinalTextOutput.$requiresExplicitFinalText.withValue(true) {
                    provider == .claude ? RemoteLLMResponseText.anthropicText(in: object) : RemoteLLMResponseText.openAIText(in: object)
                })
                guard let blocks = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [Any] else {
                    XCTFail("Typed structure was flattened or dropped: \(raw)")
                    continue
                }
                XCTAssertEqual(blocks.count, 2)
                XCTAssertEqual((blocks.first as? [String: String]), ["type": "output_text", "text": payload])
                XCTAssertEqual(blocks.last as? String, "Deleted.")
            }
        }
    }

    func testRealSelectedSessionRejectsEmptyMetadataAndErrorsBeforeAnyOutputPreparation() async throws {
        for provider in [RemoteProvider.custom, .claude] {
            let cases = (invalid + [#"{"final_text":""}"#, ""]).map { ($0, "text", 200) }
                + invalid.map { ($0, "typedFallback", 200) }
                + [("", "typedEmptyFinal", 200), ("synthetic failure", "text", 503)]
            for (payload, shape, status) in cases {
                let backend = SelectionRemoteOutputFixture(provider: provider, body: try response(payload, provider, shape), status: status)
                let fixture = try VoiceWorkflowFixture()
                defer { fixture.remove() }
                fixture.target.selectedText = "Original 👩🏽‍💻"
                useNativeProcessor(backend, in: fixture)
                try await fixture.start()
                let execution = try fixture.runtime.service(SessionServices.execution)
                let intent = SessionIntent(input: .text("rewrite politely"), mode: .selectionEdit(.custom("rewrite politely"), spokenCommand: "rewrite politely"))
                try execution.start(intent)
                let deadline = ContinuousClock.now.advanced(by: .seconds(3))
                while execution.snapshot.isBusy, execution.snapshot.selectionEditProposal == nil, ContinuousClock.now < deadline { await Task.yield() }
                let proposal = execution.snapshot.selectionEditProposal
                if proposal != nil || execution.snapshot.isBusy { execution.cancel(intent.id) }
                do { _ = try await execution.waitForCompletion(intent.id); XCTFail("Invalid generation completed") } catch {}
                XCTAssertNil(proposal)
                XCTAssertTrue(fixture.output.requests.isEmpty)
                XCTAssertEqual(fixture.target.selectedText, "Original 👩🏽‍💻")
                XCTAssertFalse(execution.applySelectionEdit(sessionID: intent.id, proposalID: UUID()))
                XCTAssertEqual(backend.requests.count, 1)
                try await fixture.runtime.stop()
                await backend.close()
            }
        }
    }

    func testCancellationDuringRemoteGenerationRejectsLateOutputInTheRealSelectedSession() async throws {
        let backend = SelectionRemoteOutputFixture(provider: .custom, body: try response(#"{"final_text":"Candidate"}"#, .custom, "text"), holdsResponse: true)
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.target.selectedText = "Original 👩🏽‍💻"
        useNativeProcessor(backend, in: fixture)
        try await fixture.start()
        let execution = try fixture.runtime.service(SessionServices.execution)
        let intent = SessionIntent(input: .text("rewrite politely"), mode: .selectionEdit(.concise, spokenCommand: "rewrite politely"))
        try execution.start(intent)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while backend.requests.isEmpty, ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertEqual(backend.requests.count, 1)
        execution.cancel(intent.id)
        await backend.releaseResponse()
        do { _ = try await execution.waitForCompletion(intent.id); XCTFail("Cancelled remote output completed") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(execution.snapshot.selectionEditProposal)
        XCTAssertTrue(fixture.output.requests.isEmpty)
        XCTAssertEqual(fixture.target.selectedText, "Original 👩🏽‍💻")
        try await fixture.runtime.stop()
        await backend.close()
    }

    private func useNativeProcessor(_ backend: SelectionRemoteOutputFixture, in fixture: VoiceWorkflowFixture) {
        fixture.recipe.selectionProcessor = { request in
            guard case .selectionEdit(let intent, let spoken) = request.mode else { throw GenerationServiceError.unsupportedOperation }
            let text = await backend.processor.processSelectionEdit(selectedText: request.text, intent: intent,
                options: backend.options, spokenCommand: spoken)
            try Task.checkCancellation()
            guard !text.isEmpty else { throw SelectionEditRecipe.Failure.emptyCandidate }
            return ProcessingResult(text: text)
        }
    }

    private func response(_ payload: String, _ provider: RemoteProvider, _ shape: String) throws -> String {
        func json(_ value: Any) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self) }
        let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8))
        if shape == "stream" || shape == "toolStream" {
            let split = payload.index(payload.startIndex, offsetBy: payload.count / 2)
            var events: [String] = []
            for fragment in [String(payload[..<split]), String(payload[split...])] {
                if provider == .claude {
                    let delta: [String: Any] = shape == "stream" ? ["type": "text_delta", "text": fragment]
                        : ["type": "input_json_delta", "partial_json": fragment]
                    events.append("data: " + (try json(["type": "content_block_delta", "index": 0, "delta": delta])))
                } else {
                    let delta: [String: Any] = shape == "stream" ? ["content": fragment]
                        : ["tool_calls": [["index": 0, "function": ["arguments": fragment]]]]
                    events.append("data: " + (try json(["choices": [["delta": delta]]])))
                }
            }
            return events.joined(separator: "\n\n") + "\n\ndata: [DONE]\n\n"
        }
        if provider == .claude {
            let block: [String: Any]
            switch shape {
            case "typedEmptyFinal": block = ["type": "final_text", "text": ""]
            case "typedFallback": block = ["type": "output_text", "text": payload]
            case "tool", "parsedTool", "toolFallback": block = ["type": "tool_use", "input": object ?? payload]
            case "contentObject": block = object as? [String: Any] ?? ["type": "text", "text": payload]
            case "json", "jsonFallback", "parsed": block = ["type": "json", "json": object ?? payload]
            default: block = ["type": "text", "text": payload]
            }
            let blocks = shape.hasSuffix("Fallback") || shape == "typedEmptyFinal" ? [block, ["type": "text", "text": "Deleted."]] : [block]
            return try json(["content": blocks])
        }
        let message: [String: Any]
        switch shape {
        case "typedEmptyFinal": message = ["content": [["type": "final_text", "text": ""], ["type": "text", "text": "Deleted."]]]
        case "typedFallback": message = ["content": [["type": "output_text", "text": payload], ["type": "text", "text": "Deleted."]]]
        case "tool": message = ["tool_calls": [["function": ["arguments": payload]]]]
        case "parsedTool": message = ["tool_calls": [["function": ["parsed_arguments": object ?? payload]]]]
        case "toolFallback": message = ["content": "Deleted.", "tool_calls": [["function": ["arguments": payload]]]]
        case "contentObject": message = ["content": object ?? payload]
        case "parsed": message = ["parsed": object ?? payload]
        case "json": message = ["content": [["type": "json", "json": object ?? payload]]]
        case "jsonFallback": message = ["content": [["type": "json", "json": object ?? payload], ["type": "text", "text": "Deleted."]]]
        default: message = ["content": payload]
        }
        return try json(["choices": [["message": message]]])
    }
}
