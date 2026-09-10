import Testing
import Foundation
@testable import Mocolamma

struct ChatAttachmentTests {
    
    @Test func testChatInputAttachmentCreation() {
        let attachment = ChatInputAttachment(name: "README.md", content: "# Title\nHello")
        #expect(attachment.name == "README.md")
        #expect(attachment.content == "# Title\nHello")
        
        let sameAttachment = attachment
        #expect(attachment == sameAttachment)
    }
    
    @Test func testBuildFullPromptWithoutAttachments() {
        let userText = "このコードを教えてください"
        let fullPrompt = ChatMessage.buildFullPrompt(userText: userText, attachments: nil)
        #expect(fullPrompt == "このコードを教えてください")
        
        let fullPromptEmpty = ChatMessage.buildFullPrompt(userText: userText, attachments: [])
        #expect(fullPromptEmpty == "このコードを教えてください")
    }
    
    @Test func testBuildFullPromptWithSingleAttachment() {
        let userText = "このマークダウンを要約して"
        let attachment = ChatInputAttachment(name: "notes.md", content: "# My Notes\nContent here")
        let fullPrompt = ChatMessage.buildFullPrompt(userText: userText, attachments: [attachment])
        
        let expected = """
        このマークダウンを要約して
        
        ===
        
        Attached File: notes.md
        
        ``````````
        # My Notes
        Content here
        ``````````
        
        ===
        
        このマークダウンを要約して
        """
        #expect(fullPrompt == expected)
    }
    
    @Test func testBuildFullPromptWithMultipleAttachments() {
        let userText = "2つのファイルを比較して"
        let file1 = ChatInputAttachment(name: "file1.txt", content: "AAA")
        let file2 = ChatInputAttachment(name: "file2.txt", content: "BBB")
        let fullPrompt = ChatMessage.buildFullPrompt(userText: userText, attachments: [file1, file2])
        
        let expected = """
        2つのファイルを比較して
        
        ===
        
        Attached File: file1.txt
        
        ``````````
        AAA
        ``````````
        
        ===
        
        Attached File: file2.txt
        
        ``````````
        BBB
        ``````````
        
        ===
        
        2つのファイルを比較して
        """
        #expect(fullPrompt == expected)
    }
    
    @Test func testBuildFullPromptWithEmptyUserText() {
        let userText = ""
        let attachment = ChatInputAttachment(name: "notes.md", content: "# Content")
        let fullPrompt = ChatMessage.buildFullPrompt(userText: userText, attachments: [attachment])
        
        let expected = """
        ===
        
        Attached File: notes.md
        
        ``````````
        # Content
        ``````````
        """
        #expect(fullPrompt == expected)
    }
    
    @Test func testChatMessageEncodingWithAttachments() throws {
        let attachment = ChatInputAttachment(name: "test.swift", content: "print(42)")
        let message = ChatMessage(
            role: "user",
            content: "コードを解説して",
            attachments: [attachment]
        )
        
        // メモリ上のcontentはクリーンなテキストのまま
        #expect(message.content == "コードを解説して")
        #expect(message.attachments?.count == 1)
        
        // JSONエンコードするとcontentがプロンプト形式に自動展開される
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(message)
        let json = String(decoding: data, as: UTF8.self)
        
        #expect(json.contains("\"role\":\"user\""))
        #expect(json.contains("Attached File: test.swift"))
        #expect(json.contains("print(42)"))
    }
    
    @Test func testChatMessageEncodingWithoutAttachments() throws {
        let message = ChatMessage(
            role: "user",
            content: "こんにちは"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        let json = String(decoding: data, as: UTF8.self)
        
        #expect(json.contains("\"content\":\"こんにちは\""))
        #expect(!json.contains("Attached File:"))
    }
    
    @Test func testPDFAttachmentDetection() {
        let textAttachment = ChatInputAttachment(name: "test.txt", content: "hello")
        let pdfAttachment = ChatInputAttachment(name: "document.pdf", content: "base64data")
        let upperPDFAttachment = ChatInputAttachment(name: "DOCUMENT.PDF", content: "base64data")
        
        #expect(!textAttachment.isPDF)
        #expect(pdfAttachment.isPDF)
        #expect(upperPDFAttachment.isPDF)
    }
    
    @Test func testBuildFullPromptWithPDFAttachment() {
        let userText = "PDFを要約して"
        let pdfContent = """
        ===
        
        Attached File: sample.pdf
        
        Page: 1 / 2
        
        ``````````
        Page 1 Content
        ``````````
        
        ---
        
        Page: 2 / 2 (Extracted by OCR)
        
        ``````````
        Page 2 OCR Content
        ``````````
        """
        let pdfAttachment = ChatInputAttachment(name: "sample.pdf", content: pdfContent)
        let fullPrompt = ChatMessage.buildFullPrompt(userText: userText, attachments: [pdfAttachment])
        
        let expected = """
        PDFを要約して
        
        ===
        
        Attached File: sample.pdf
        
        Page: 1 / 2
        
        ``````````
        Page 1 Content
        ``````````
        
        ---
        
        Page: 2 / 2 (Extracted by OCR)
        
        ``````````
        Page 2 OCR Content
        ``````````
        
        ===
        
        PDFを要約して
        """
        #expect(fullPrompt == expected)
    }
    
    @Test func testChatMessageEncodingWithDirectAndPDFImages() throws {
        let directImage = "direct_image_base64"
        let pdfImage1 = "pdf_page_1_base64"
        let pdfImage2 = "pdf_page_2_base64"
        
        let message = ChatMessage(
            role: "user",
            content: "画像とPDFを分析して",
            images: [directImage],
            pdfImages: [pdfImage1, pdfImage2]
        )
        
        // メッセージオブジェクトのimagesプロパティにはユーザ添付画像のみ保持される（UI表示用）
        #expect(message.images == [directImage])
        #expect(message.pdfImages == [pdfImage1, pdfImage2])
        
        // API送信用にエンコードすると、imagesに直接画像とPDF画像が結合されて出力される
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        
        struct DecodedPayload: Decodable {
            let role: String
            let content: String
            let images: [String]?
        }
        
        let payload = try JSONDecoder().decode(DecodedPayload.self, from: data)
        #expect(payload.images == [directImage, pdfImage1, pdfImage2])
    }
}
