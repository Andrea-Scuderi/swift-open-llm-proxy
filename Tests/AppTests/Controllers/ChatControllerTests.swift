import Testing
import VaporTesting
@testable import App

@Suite("ChatController input validation")
struct ChatControllerInputValidationTests {

    private func makeApp() async throws -> Application {
        let app = try await Application.make(.testing)
        // BedrockService is never called for validation-rejection tests — the guard
        // throws before any Bedrock API call is made.
        let bedrock = BedrockService(region: "us-east-1")
        let controller = ChatController(
            bedrockService: bedrock,
            modelMapper: ModelMapper(defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"),
            requestTranslator: RequestTranslator(),
            responseTranslator: ResponseTranslator()
        )
        try app.register(collection: controller)
        return app
    }

    @Test("model name at limit is accepted")
    func modelNameAtLimitIsAccepted() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        let longModel = String(repeating: "a", count: 128)
        let body = """
        {"model":"\(longModel)","messages":[{"role":"user","content":"hi"}],"max_tokens":10}
        """
        var headers = HTTPHeaders()
        headers.contentType = .json

        try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
            // Model name is valid (128 chars) — fails later at Bedrock, not at our guard.
            #expect(res.status != .badRequest)
        }
    }

    @Test("model name exceeding 128 chars returns 400")
    func modelNameTooLongReturns400() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        let longModel = String(repeating: "a", count: 129)
        let body = """
        {"model":"\(longModel)","messages":[{"role":"user","content":"hi"}],"max_tokens":10}
        """
        var headers = HTTPHeaders()
        headers.contentType = .json

        try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
            #expect(res.status == .badRequest)
        }
    }

    @Test("exactly 100 messages is accepted")
    func exactly100MessagesIsAccepted() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        let msgs = (0..<100).map { _ in "{\"role\":\"user\",\"content\":\"hi\"}" }.joined(separator: ",")
        let body = "{\"model\":\"claude-sonnet\",\"messages\":[\(msgs)],\"max_tokens\":10}"
        var headers = HTTPHeaders()
        headers.contentType = .json

        try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
            // Guard passes; may fail at Bedrock (no real creds), but not at our validation.
            #expect(res.status != .badRequest)
        }
    }

    @Test("101 messages returns 400")
    func tooManyMessagesReturns400() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        let msgs = (0..<101).map { _ in "{\"role\":\"user\",\"content\":\"hi\"}" }.joined(separator: ",")
        let body = "{\"model\":\"claude-sonnet\",\"messages\":[\(msgs)],\"max_tokens\":10}"
        var headers = HTTPHeaders()
        headers.contentType = .json

        try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
            #expect(res.status == .badRequest)
        }
    }

    @Test("message content at 65536 chars is accepted")
    func messageContentAtLimitIsAccepted() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        let longText = String(repeating: "x", count: 65_536)
        let body = "{\"model\":\"claude-sonnet\",\"messages\":[{\"role\":\"user\",\"content\":\"\(longText)\"}],\"max_tokens\":10}"
        var headers = HTTPHeaders()
        headers.contentType = .json

        try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
            #expect(res.status != .badRequest)
        }
    }

    @Test("message content exceeding 65536 chars returns 400")
    func messageContentTooLongReturns400() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        let longText = String(repeating: "x", count: 65_537)
        let body = "{\"model\":\"claude-sonnet\",\"messages\":[{\"role\":\"user\",\"content\":\"\(longText)\"}],\"max_tokens\":10}"
        var headers = HTTPHeaders()
        headers.contentType = .json

        try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
            #expect(res.status == .badRequest)
        }
    }
}
