import Testing
import VaporTesting
import SotoBedrockRuntime
@testable import App

// MARK: - Mock

private struct MockBedrockConversable: BedrockConversable {
    enum Behavior {
        case success(BedrockRuntime.ConverseResponse)
        case streamSuccess([BedrockRuntime.ConverseStreamOutput])
        case failure(Error)
    }

    let behavior: Behavior

    func converse(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration?
    ) async throws -> BedrockRuntime.ConverseResponse {
        switch behavior {
        case .success(let response): return response
        case .streamSuccess:         throw MockBedrockError.wrongMethodCalled
        case .failure(let error):    throw error
        }
    }

    func converseStreamRaw(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration?
    ) async throws -> AsyncThrowingStream<BedrockRuntime.ConverseStreamOutput, Error> {
        switch behavior {
        case .streamSuccess(let events):
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        case .success:            throw MockBedrockError.wrongMethodCalled
        case .failure(let error): throw error
        }
    }
}

private enum MockBedrockError: Error {
    case wrongMethodCalled
}

// Type name contains "Throttling" — matched by BedrockService.httpStatus(for:)
private struct MockThrottlingError: Error {}

// MARK: - Helpers

private func mockConverseResponse() -> BedrockRuntime.ConverseResponse {
    BedrockRuntime.ConverseResponse(
        metrics: BedrockRuntime.ConverseMetrics(latencyMs: 0),
        output: BedrockRuntime.ConverseOutput(
            message: BedrockRuntime.Message(
                content: [.text("Hello from mock")],
                role: .assistant
            )
        ),
        stopReason: .endTurn,
        usage: BedrockRuntime.TokenUsage(inputTokens: 10, outputTokens: 5, totalTokens: 15)
    )
}

private func minimalStreamEvents() -> [BedrockRuntime.ConverseStreamOutput] {
    [
        .contentBlockDelta(BedrockRuntime.ContentBlockDeltaEvent(
            contentBlockIndex: 0,
            delta: .text("Hello")
        )),
        .contentBlockStop(BedrockRuntime.ContentBlockStopEvent(
            contentBlockIndex: 0
        )),
        .messageStop(BedrockRuntime.MessageStopEvent(
            stopReason: .endTurn
        )),
        .metadata(BedrockRuntime.ConverseStreamMetadataEvent(
            metrics: BedrockRuntime.ConverseStreamMetrics(latencyMs: 0),
            usage: BedrockRuntime.TokenUsage(inputTokens: 10, outputTokens: 5, totalTokens: 15)
        )),
    ]
}

// MARK: - Token Counting Tests

@Suite("MessagesController Token Counting")
struct MessagesControllerTests {

    private func makeApp() async throws -> Application {
        let app = try await Application.make(.testing)
        let mock = MockBedrockConversable(behavior: .success(mockConverseResponse()))
        let controller = MessagesController(
            bedrockService: mock,
            modelMapper: ModelMapper(defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"),
            requestTranslator: AnthropicRequestTranslator(),
            responseTranslator: AnthropicResponseTranslator()
        )
        try app.register(collection: controller)
        return app
    }

    @Test("single 12-char message estimates 3 tokens")
    func countTokensSingleMessageEstimatesCorrectly() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        // "Hello, world" = 12 chars → 12 / 4 = 3 tokens
        let body = """
        {"model":"claude-sonnet","messages":[{"role":"user","content":"Hello, world"}],"max_tokens":100}
        """
        var headers = HTTPHeaders()
        headers.contentType = .json

        try await app.test(.POST, "/v1/messages/count_tokens", headers: headers, body: ByteBuffer(string: body)) { res async in
            #expect(res.status == .ok)
            if let resp = try? res.content.decode(AnthropicCountTokensResponse.self) {
                #expect(resp.inputTokens == 3)
            }
        }
    }

    @Test("2-char message returns minimum of 1 token")
    func countTokensShortMessageReturnsMinimumOne() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        // "Hi" = 2 chars → 2 / 4 = 0 → max(1, 0) = 1 token
        let body = """
        {"model":"claude-sonnet","messages":[{"role":"user","content":"Hi"}],"max_tokens":100}
        """
        var headers = HTTPHeaders()
        headers.contentType = .json

        try await app.test(.POST, "/v1/messages/count_tokens", headers: headers, body: ByteBuffer(string: body)) { res async in
            #expect(res.status == .ok)
            if let resp = try? res.content.decode(AnthropicCountTokensResponse.self) {
                #expect(resp.inputTokens == 1)
            }
        }
    }

    @Test("system prompt chars counted toward total")
    func countTokensSystemPromptCounts() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        // "Hello" (5) + "Hi" (2) = 7 chars → 7 / 4 = 1 token
        let body = """
        {"model":"claude-sonnet","messages":[{"role":"user","content":"Hi"}],"system":"Hello","max_tokens":100}
        """
        var headers = HTTPHeaders()
        headers.contentType = .json

        try await app.test(.POST, "/v1/messages/count_tokens", headers: headers, body: ByteBuffer(string: body)) { res async in
            #expect(res.status == .ok)
            if let resp = try? res.content.decode(AnthropicCountTokensResponse.self) {
                #expect(resp.inputTokens == 1)
            }
        }
    }

    @Test("multiple messages chars aggregated")
    func countTokensMultipleMessagesAggregates() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        // "Hello!!!" (8) + "Worldxxx" (8) = 16 chars → 16 / 4 = 4 tokens
        let body = """
        {"model":"claude-sonnet","messages":[{"role":"user","content":"Hello!!!"},{"role":"assistant","content":"Worldxxx"}],"max_tokens":100}
        """
        var headers = HTTPHeaders()
        headers.contentType = .json

        try await app.test(.POST, "/v1/messages/count_tokens", headers: headers, body: ByteBuffer(string: body)) { res async in
            #expect(res.status == .ok)
            if let resp = try? res.content.decode(AnthropicCountTokensResponse.self) {
                #expect(resp.inputTokens == 4)
            }
        }
    }
}

// MARK: - Non-Streaming Tests

@Suite("MessagesController non-streaming")
struct MessagesControllerNonStreamingTests {

    private let validBody = """
    {"model":"claude-sonnet","messages":[{"role":"user","content":"Hello"}],"max_tokens":100}
    """

    private func makeApp(behavior: MockBedrockConversable.Behavior) async throws -> Application {
        let app = try await Application.make(.testing)
        let mock = MockBedrockConversable(behavior: behavior)
        let controller = MessagesController(
            bedrockService: mock,
            modelMapper: ModelMapper(defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"),
            requestTranslator: AnthropicRequestTranslator(),
            responseTranslator: AnthropicResponseTranslator()
        )
        try app.register(collection: controller)
        return app
    }

    @Test("returns OK for valid request")
    func returnsOKForValidRequest() async throws {
        let app = try await makeApp(behavior: .success(mockConverseResponse()))
        defer { Task { try await app.asyncShutdown() } }

        var headers = HTTPHeaders()
        headers.contentType = .json

        try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: validBody)) { res async in
            #expect(res.status == .ok)
        }
    }

    @Test("response contains required fields")
    func responseContainsRequiredFields() async throws {
        let app = try await makeApp(behavior: .success(mockConverseResponse()))
        defer { Task { try await app.asyncShutdown() } }

        var headers = HTTPHeaders()
        headers.contentType = .json

        try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: validBody)) { res async in
            #expect(res.status == .ok)
            if let resp = try? res.content.decode(AnthropicResponse.self) {
                #expect(resp.type == "message")
                #expect(resp.role == "assistant")
                #expect(!resp.id.isEmpty)
                #expect(resp.stopReason == "end_turn")
            }
        }
    }

    @Test("response content contains mock text")
    func responseContentContainsMockText() async throws {
        let app = try await makeApp(behavior: .success(mockConverseResponse()))
        defer { Task { try await app.asyncShutdown() } }

        var headers = HTTPHeaders()
        headers.contentType = .json

        try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: validBody)) { res async in
            #expect(res.status == .ok)
            if let resp = try? res.content.decode(AnthropicResponse.self) {
                let texts = resp.content.compactMap(\.text)
                #expect(texts.contains("Hello from mock"))
            }
        }
    }

    @Test("throttling error returns 429")
    func throttlingErrorReturns429() async throws {
        let app = try await makeApp(behavior: .failure(MockThrottlingError()))
        defer { Task { try await app.asyncShutdown() } }

        var headers = HTTPHeaders()
        headers.contentType = .json

        try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: validBody)) { res async in
            #expect(res.status == .tooManyRequests)
        }
    }
}

// MARK: - Streaming Tests

@Suite("MessagesController streaming")
struct MessagesControllerStreamingTests {

    private let streamingBody = """
    {"model":"claude-sonnet","messages":[{"role":"user","content":"Hello"}],"max_tokens":100,"stream":true}
    """

    private func makeApp(behavior: MockBedrockConversable.Behavior) async throws -> Application {
        let app = try await Application.make(.testing)
        let mock = MockBedrockConversable(behavior: behavior)
        let controller = MessagesController(
            bedrockService: mock,
            modelMapper: ModelMapper(defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"),
            requestTranslator: AnthropicRequestTranslator(),
            responseTranslator: AnthropicResponseTranslator()
        )
        try app.register(collection: controller)
        return app
    }

    @Test("returns OK with SSE content type")
    func returnsOKWithSSEContentType() async throws {
        let app = try await makeApp(behavior: .streamSuccess(minimalStreamEvents()))
        defer { Task { try await app.asyncShutdown() } }

        var headers = HTTPHeaders()
        headers.contentType = .json

        try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: streamingBody)) { res async in
            #expect(res.status == .ok)
            #expect(res.headers.first(name: .contentType)?.contains("text/event-stream") == true)
        }
    }

    @Test("SSE body contains message_start event")
    func sseBodyContainsMessageStart() async throws {
        let app = try await makeApp(behavior: .streamSuccess(minimalStreamEvents()))
        defer { Task { try await app.asyncShutdown() } }

        var headers = HTTPHeaders()
        headers.contentType = .json

        try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: streamingBody)) { res async in
            let bodyStr = res.body.string
            #expect(bodyStr.contains("event: message_start"))
        }
    }

    @Test("SSE body contains ping event")
    func sseBodyContainsPing() async throws {
        let app = try await makeApp(behavior: .streamSuccess(minimalStreamEvents()))
        defer { Task { try await app.asyncShutdown() } }

        var headers = HTTPHeaders()
        headers.contentType = .json

        try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: streamingBody)) { res async in
            let bodyStr = res.body.string
            #expect(bodyStr.contains("event: ping"))
        }
    }

    @Test("SSE body contains message_stop event")
    func sseBodyContainsMessageStop() async throws {
        let app = try await makeApp(behavior: .streamSuccess(minimalStreamEvents()))
        defer { Task { try await app.asyncShutdown() } }

        var headers = HTTPHeaders()
        headers.contentType = .json

        try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: streamingBody)) { res async in
            let bodyStr = res.body.string
            #expect(bodyStr.contains("event: message_stop"))
        }
    }

    @Test("throttling error during setup returns 429")
    func throttlingErrorDuringSetupReturns429() async throws {
        let app = try await makeApp(behavior: .failure(MockThrottlingError()))
        defer { Task { try await app.asyncShutdown() } }

        var headers = HTTPHeaders()
        headers.contentType = .json

        try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: streamingBody)) { res async in
            #expect(res.status == .tooManyRequests)
        }
    }
}
