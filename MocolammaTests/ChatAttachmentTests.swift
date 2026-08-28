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
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(message)
        let json = String(decoding: data, as: UTF8.self)
        
        #expect(json.contains("\"content\":\"こんにちは\""))
        #expect(!json.contains("Attached File:"))
    }
}
