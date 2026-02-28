import Testing
import Foundation
@testable import App

@Suite("ChatMessage Custom Decoding")
struct ChatMessageDecodingTests {

    private func decode(_ json: String) throws -> ChatMessage {
        try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
    }

    @Test("decodes plain string content")
    func decodesPlainStringContent() throws {
        let msg = try decode("{\"role\":\"user\",\"content\":\"Hello\"}")
        #expect(msg.content.textOnly == "Hello")
    }

    @Test("decodes content parts array joining text parts")
    func decodesContentPartsArray() throws {
        let json = "{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"Hi\"},{\"type\":\"text\",\"text\":\" there\"}]}"
        #expect(try decode(json).content.textOnly == "Hi there")
    }

    @Test("content parts skips non-text types without image_url")
    func contentPartsSkipsNonTextTypes() throws {
        let json = "{\"role\":\"user\",\"content\":[{\"type\":\"image\",\"text\":null},{\"type\":\"text\",\"text\":\"Hi\"}]}"
        #expect(try decode(json).content.textOnly == "Hi")
    }

    @Test("decodes role correctly")
    func decodesRoleCorrectly() throws {
        #expect(try decode("{\"role\":\"assistant\",\"content\":\"Howdy\"}").role == "assistant")
    }

    @Test("content parts with all non-text types yields empty string")
    func contentPartsWithNilTextYieldsEmpty() throws {
        let json = "{\"role\":\"user\",\"content\":[{\"type\":\"image\"}]}"
        #expect(try decode(json).content.textOnly == "")
    }

    @Test("image_url with data URL decodes as image part")
    func imageURLDataURLDecodesAsImagePart() throws {
        let dataURL = "data:image/png;base64,iVBORw0KGgo="
        let json = """
        {"role":"user","content":[{"type":"image_url","image_url":{"url":"\(dataURL)"}},{"type":"text","text":"Describe"}]}
        """
        let msg = try decode(json)
        #expect(msg.content.hasImages)
        #expect(msg.content.textOnly == "Describe")
        if case .parts(let parts) = msg.content {
            #expect(parts.count == 2)
            if case .image(let img) = parts[0] {
                #expect(img.format == "png")
                #expect(img.base64Data == "iVBORw0KGgo=")
            } else {
                Issue.record("Expected first part to be .image")
            }
        } else {
            Issue.record("Expected .parts content")
        }
    }

    @Test("image_url with HTTPS URL is silently dropped")
    func imageURLWithHTTPSIsDropped() throws {
        let json = """
        {"role":"user","content":[{"type":"image_url","image_url":{"url":"https://example.com/image.png"}},{"type":"text","text":"Hi"}]}
        """
        let msg = try decode(json)
        #expect(!msg.content.hasImages)
        #expect(msg.content.textOnly == "Hi")
    }

    @Test("image_url with unsupported MIME type is dropped")
    func imageURLWithNonImageMIMEIsDropped() throws {
        let json = """
        {"role":"user","content":[{"type":"image_url","image_url":{"url":"data:application/pdf;base64,abc"}},{"type":"text","text":"Hi"}]}
        """
        let msg = try decode(json)
        #expect(!msg.content.hasImages)
        #expect(msg.content.textOnly == "Hi")
    }

    @Test("mixed text and image parts preserve order via MessageContent")
    func mixedPartsPreserveOrder() throws {
        let dataURL = "data:image/jpeg;base64,/9j/4="
        let json = """
        {"role":"user","content":[{"type":"text","text":"Before"},{"type":"image_url","image_url":{"url":"\(dataURL)"}},{"type":"text","text":"After"}]}
        """
        let msg = try decode(json)
        #expect(msg.content.hasImages)
        #expect(msg.content.textOnly == "BeforeAfter")
        if case .parts(let parts) = msg.content {
            #expect(parts.count == 3)
        } else {
            Issue.record("Expected .parts content")
        }
    }

    @Test("MessageContent.hasImages is false for plain text")
    func hasImagesIsFalseForPlainText() throws {
        let msg = try decode("{\"role\":\"user\",\"content\":\"Hello\"}")
        #expect(!msg.content.hasImages)
    }

    @Test("convenience init produces text content")
    func convenienceInitProducesTextContent() {
        let msg = ChatMessage(role: "user", content: "Hello")
        #expect(msg.content.textOnly == "Hello")
        #expect(!msg.content.hasImages)
    }
}
