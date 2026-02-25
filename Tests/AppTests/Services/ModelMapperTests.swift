import Testing
@testable import App

@Suite("ModelMapper")
struct ModelMapperTests {

    let mapper = ModelMapper(defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0")

    @Test("gpt-4 maps to Sonnet 4.5")
    func gpt4MapsToSonnet() {
        #expect(mapper.bedrockModelID(for: "gpt-4") == "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
    }

    @Test("gpt-3.5-turbo maps to Haiku 4.5")
    func gpt35TurboMapsToHaiku() {
        #expect(mapper.bedrockModelID(for: "gpt-3.5-turbo") == "us.anthropic.claude-haiku-4-5-20251001-v1:0")
    }

    @Test("native us.anthropic Bedrock model ID passes through")
    func passthroughNativeBedrockID() {
        let nativeID = "us.anthropic.claude-3-opus-20240229-v1:0"
        #expect(mapper.bedrockModelID(for: nativeID) == nativeID)
    }

    @Test("unknown model falls back to default")
    func unknownModelFallsToDefault() {
        #expect(mapper.bedrockModelID(for: "some-unknown-model") == "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
    }

    @Test("claude-3-5-sonnet alias resolves to v2 model")
    func claudeSonnetAlias() {
        #expect(mapper.bedrockModelID(for: "claude-3-5-sonnet") == "us.anthropic.claude-3-5-sonnet-20241022-v2:0")
    }

    @Test("gpt-4o maps to Sonnet 4.5")
    func gpt4oMapsToSonnet() {
        #expect(mapper.bedrockModelID(for: "gpt-4o") == "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
    }

    @Test("gpt-4-turbo maps to Sonnet 4.5")
    func gpt4TurboMapsToSonnet() {
        #expect(mapper.bedrockModelID(for: "gpt-4-turbo") == "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
    }

    @Test("claude-opus-4-6 alias resolves")
    func claudeOpus4Alias() {
        #expect(mapper.bedrockModelID(for: "claude-opus-4-6") == "us.anthropic.claude-opus-4-6-v1")
    }

    @Test("amazon. prefix model passes through unchanged")
    func nativeBedrockWithAmazonPrefix() {
        let nativeID = "amazon.titan-text-express-v1"
        #expect(mapper.bedrockModelID(for: nativeID) == nativeID)
    }

    @Test("empty string falls back to default")
    func emptyStringFallsToDefault() {
        #expect(mapper.bedrockModelID(for: "") == "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
    }

    @Test("nova-pro alias resolves to Amazon Nova Pro")
    func novaProAliasResolvesToAmazonNovaPro() {
        #expect(mapper.bedrockModelID(for: "nova-pro") == "us.amazon.nova-pro-v1:0")
    }

    @Test("nova-lite alias resolves to Amazon Nova Lite")
    func novaLiteAliasResolvesToAmazonNovaLite() {
        #expect(mapper.bedrockModelID(for: "nova-lite") == "us.amazon.nova-lite-v1:0")
    }

    @Test("nova-micro alias resolves to Amazon Nova Micro")
    func novaMicroAliasResolvesToAmazonNovaMicro() {
        #expect(mapper.bedrockModelID(for: "nova-micro") == "us.amazon.nova-micro-v1:0")
    }

    @Test("us.amazon. cross-region model ID passes through unchanged")
    func passthroughUsAmazonCrossRegionID() {
        let nativeID = "us.amazon.nova-pro-v1:0"
        #expect(mapper.bedrockModelID(for: nativeID) == nativeID)
    }

    @Test("deepseek-r1 alias resolves to us.deepseek.r1-v1:0")
    func deepseekR1AliasResolves() {
        #expect(mapper.bedrockModelID(for: "deepseek-r1") == "us.deepseek.r1-v1:0")
    }

    @Test("native us.deepseek model ID passes through unchanged")
    func passthroughNativeDeepseekID() {
        let nativeID = "us.deepseek.r1-v1:0"
        #expect(mapper.bedrockModelID(for: nativeID) == nativeID)
    }

    @Test("native us.meta model ID passes through unchanged")
    func passthroughNativeMetaID() {
        let nativeID = "us.meta.llama3-3-70b-instruct-v1:0"
        #expect(mapper.bedrockModelID(for: nativeID) == nativeID)
    }

    @Test("native mistral. model ID passes through unchanged")
    func passthroughNativeMistralID() {
        let nativeID = "mistral.mistral-large-2407-v1:0"
        #expect(mapper.bedrockModelID(for: nativeID) == nativeID)
    }

    @Test("llama-3-3-70b alias resolves correctly")
    func llama33Alias() {
        #expect(mapper.bedrockModelID(for: "llama-3-3-70b") == "us.meta.llama3-3-70b-instruct-v1:0")
    }

    @Test("mistral-large alias resolves to Bedrock Mistral Large")
    func mistralLargeAlias() {
        #expect(mapper.bedrockModelID(for: "mistral-large") == "mistral.mistral-large-2407-v1:0")
    }

    @Test("command-r-plus alias resolves to Cohere Command R+")
    func commandRPlusAlias() {
        #expect(mapper.bedrockModelID(for: "command-r-plus") == "cohere.command-r-plus-v1:0")
    }

    @Test("jamba-large alias resolves to AI21 Jamba 1.5 Large")
    func jamba15LargeAlias() {
        #expect(mapper.bedrockModelID(for: "jamba-large") == "ai21.jamba-1-5-large-v1:0")
    }

    @Test("llama-4-maverick alias resolves correctly")
    func llama4MaverickAlias() {
        #expect(mapper.bedrockModelID(for: "llama-4-maverick") == "us.meta.llama4-maverick-17b-instruct-v1:0")
    }

    @Test("native cohere. model ID passes through unchanged")
    func passthroughNativeCohereID() {
        let nativeID = "cohere.command-r-plus-v1:0"
        #expect(mapper.bedrockModelID(for: nativeID) == nativeID)
    }

    // MARK: - Model name resolution (tier 3)

    @Test("model name 'Claude 3.5 Sonnet v2' resolves to Bedrock ID")
    func claudeSonnetV2NameResolvesToBedrockID() {
        #expect(mapper.bedrockModelID(for: "Claude 3.5 Sonnet v2") == "us.anthropic.claude-3-5-sonnet-20241022-v2:0")
    }

    @Test("model name 'Nova Pro' resolves to Bedrock ID")
    func novaProNameResolvesToBedrockID() {
        #expect(mapper.bedrockModelID(for: "Nova Pro") == "us.amazon.nova-pro-v1:0")
    }

    @Test("model name 'DeepSeek-R1' resolves to Bedrock ID")
    func deepSeekR1NameResolvesToBedrockID() {
        #expect(mapper.bedrockModelID(for: "DeepSeek-R1") == "us.deepseek.r1-v1:0")
    }

    @Test("model name 'Llama 3.3 70B Instruct' resolves to Bedrock ID")
    func llama33NameResolvesToBedrockID() {
        #expect(mapper.bedrockModelID(for: "Llama 3.3 70B Instruct") == "us.meta.llama3-3-70b-instruct-v1:0")
    }

    @Test("model name 'Mistral Large (24.02)' resolves to Bedrock ID")
    func mistralLargeNameResolvesToBedrockID() {
        #expect(mapper.bedrockModelID(for: "Mistral Large (24.02)") == "mistral.mistral-large-2402-v1:0")
    }

    @Test("model name 'Command R+' resolves to Bedrock ID")
    func commandRPlusNameResolvesToBedrockID() {
        #expect(mapper.bedrockModelID(for: "Command R+") == "cohere.command-r-plus-v1:0")
    }

    @Test("model name 'Jamba 1.5 Large' resolves to Bedrock ID")
    func jamba15LargeNameResolvesToBedrockID() {
        #expect(mapper.bedrockModelID(for: "Jamba 1.5 Large") == "ai21.jamba-1-5-large-v1:0")
    }
}
