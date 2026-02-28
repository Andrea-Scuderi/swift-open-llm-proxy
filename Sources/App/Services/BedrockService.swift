import Vapor
import SotoCore
import SotoBedrockRuntime
import SotoBedrock

// MARK: - FoundationModelInfo

struct FoundationModelInfo: Sendable {
    let modelId: String
    let modelName: String?
    let providerName: String?
    let isActive: Bool
}

// MARK: - Protocol

protocol FoundationModelListable: Sendable {
    func listFoundationModels() async throws -> [FoundationModelInfo]
}

// MARK: - Actor

actor BedrockService {
    private let client: AWSClient
    let runtime: BedrockRuntime
    let bedrock: Bedrock

    init(region: String, profile: String? = nil, bedrockAPIKey: String? = nil) {
        if let apiKey = bedrockAPIKey {
            // Bedrock API key authentication: inject Bearer token; skip SigV4 (empty credentials
            // cause signHeaders to return early without adding an Authorization header).
            self.client = AWSClient(
                credentialProvider: .empty,
                middleware: AWSEditHeadersMiddleware(.replace(name: "Authorization", value: "Bearer \(apiKey)"))
            )
        } else {
            let credentialProvider: CredentialProviderFactory = profile.map {
                .configFile(profile: $0)
            } ?? .default
            self.client = AWSClient(credentialProvider: credentialProvider)
        }
        self.runtime = BedrockRuntime(client: client, region: .init(rawValue: region))
        self.bedrock = Bedrock(client: client, region: .init(rawValue: region))
    }

    deinit {
        try? client.syncShutdown()
    }

    // MARK: - Non-streaming

    func converse(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration? = nil
    ) async throws -> BedrockRuntime.ConverseResponse {
        let request = BedrockRuntime.ConverseRequest(
            inferenceConfig: inferenceConfig,
            messages: messages,
            modelId: modelID,
            system: system.isEmpty ? nil : system,
            toolConfig: toolConfig
        )
        return try await runtime.converse(request)
    }

    // MARK: - Streaming
    // nonisolated + async throws: the Bedrock handshake (runtime.converseStream) happens
    // here before we return the stream, so auth/access errors are thrown to the caller
    // while it can still send a proper HTTP error response rather than a 200 SSE body.
    // `runtime` is a `let`, safe to access from a nonisolated context.
    /// Streaming for the OpenAI `/v1/chat/completions` path — yields plain text deltas only.
    nonisolated func converseStream(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration
    ) async throws -> AsyncThrowingStream<String, Error> {
        let request = BedrockRuntime.ConverseStreamRequest(
            inferenceConfig: inferenceConfig,
            messages: messages,
            modelId: modelID,
            system: system.isEmpty ? nil : system
        )
        let response = try await runtime.converseStream(request)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // response.stream is AWSEventStream<ConverseStreamOutput> (non-optional)
                    for try await event in response.stream {
                        switch event {
                        case .contentBlockDelta(let deltaEvent):
                            switch deltaEvent.delta {
                            case .text(let text):
                                continuation.yield(text)
                            default:
                                break
                            }
                        case .messageStop:
                            continuation.finish()
                            return
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Streaming for the Anthropic `/v1/messages` path — yields raw Bedrock events
    /// so the caller can translate them into Anthropic SSE format (including tool use).
    nonisolated func converseStreamRaw(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration? = nil
    ) async throws -> AsyncThrowingStream<BedrockRuntime.ConverseStreamOutput, Error> {
        let request = BedrockRuntime.ConverseStreamRequest(
            inferenceConfig: inferenceConfig,
            messages: messages,
            modelId: modelID,
            system: system.isEmpty ? nil : system,
            toolConfig: toolConfig
        )
        let response = try await runtime.converseStream(request)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await event in response.stream {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Foundation Models

    func listFoundationModels() async throws -> [FoundationModelInfo] {
        let input = Bedrock.ListFoundationModelsRequest(
            byInferenceType: .onDemand,
            byOutputModality: .text
        )
        let response = try await bedrock.listFoundationModels(input)
        return (response.modelSummaries ?? []).map { summary in
            FoundationModelInfo(
                modelId: summary.modelId,
                modelName: summary.modelName,
                providerName: summary.providerName,
                isActive: summary.modelLifecycle?.status == .active
            )
        }
    }
}

// MARK: - FoundationModelListable Conformance

extension BedrockService: FoundationModelListable {}

// MARK: - BedrockConversable

protocol BedrockConversable: Sendable {
    func converse(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration?
    ) async throws -> BedrockRuntime.ConverseResponse

    func converseStreamRaw(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration?
    ) async throws -> AsyncThrowingStream<BedrockRuntime.ConverseStreamOutput, Error>
}

// MARK: - BedrockConversable Conformance

extension BedrockService: BedrockConversable {}

// MARK: - Error Mapping

extension BedrockService {
    static func httpStatus(for error: Error) -> HTTPResponseStatus {
        let typeName = String(describing: type(of: error)).lowercased()
        if typeName.contains("throttling") {
            return .tooManyRequests
        } else if typeName.contains("validation") {
            return .badRequest
        } else if typeName.contains("accessdenied") {
            return .forbidden
        } else if typeName.contains("resourcenotfound") || typeName.contains("modelnotfound") {
            return .notFound
        } else if typeName.contains("serviceunavailable") {
            return .serviceUnavailable
        }
        return .internalServerError
    }

    /// Returns a client-safe error reason (HTTP status phrase only).
    /// Full error details are logged server-side; AWS internals are never sent to clients.
    static func clientSafeReason(for error: Error) -> String {
        httpStatus(for: error).reasonPhrase
    }
}
