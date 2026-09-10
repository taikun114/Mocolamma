import Testing
import Foundation
@testable import Mocolamma

struct ThinkingOptionTests {
    
    @Test func testThinkingOptionAPIValues() {
        #expect(ThinkingOption.defaultOption.apiValue == nil)
        #expect(ThinkingOption.off.apiValue == .bool(false))
        #expect(ThinkingOption.low.apiValue == .string("low"))
        #expect(ThinkingOption.medium.apiValue == .string("medium"))
        #expect(ThinkingOption.high.apiValue == .string("high"))
        #expect(ThinkingOption.max.apiValue == .string("max"))
    }
    
    @Test func testThinkingOptionIsThinkingRequested() {
        #expect(!ThinkingOption.defaultOption.isThinkingRequested)
        #expect(!ThinkingOption.off.isThinkingRequested)
        #expect(ThinkingOption.low.isThinkingRequested)
        #expect(ThinkingOption.medium.isThinkingRequested)
        #expect(ThinkingOption.high.isThinkingRequested)
        #expect(ThinkingOption.max.isThinkingRequested)
    }
    
    @Test func testChatRequestEncoding() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        
        // 1. デフォルト（nil）の場合
        let defaultReq = ChatRequest(
            model: "test-model",
            messages: [ChatMessage(role: "user", content: "Hello")],
            stream: true,
            think: ThinkingOption.defaultOption.apiValue,
            keepAlive: nil,
            options: nil,
            tools: nil
        )
        let defaultData = try encoder.encode(defaultReq)
        let defaultJson = String(decoding: defaultData, as: UTF8.self)
        #expect(!defaultJson.contains("\"think\""))
        
        // 2. オフ（false）の場合
        let offReq = ChatRequest(
            model: "test-model",
            messages: [ChatMessage(role: "user", content: "Hello")],
            stream: true,
            think: ThinkingOption.off.apiValue,
            keepAlive: nil,
            options: nil,
            tools: nil
        )
        let offData = try encoder.encode(offReq)
        let offJson = try JSONDecoder().decode([String: JSONValue].self, from: offData)
        #expect(offJson["think"] == .bool(false))
        
        // 3. 各シンキングレベル（low, medium, high, max）の場合
        let levels: [(ThinkingOption, String)] = [
            (.low, "low"),
            (.medium, "medium"),
            (.high, "high"),
            (.max, "max")
        ]
        
        for (option, expectedString) in levels {
            let req = ChatRequest(
                model: "test-model",
                messages: [ChatMessage(role: "user", content: "Hello")],
                stream: true,
                think: option.apiValue,
                keepAlive: nil,
                options: nil,
                tools: nil
            )
            let data = try encoder.encode(req)
            let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
            #expect(json["think"] == .string(expectedString))
        }
    }
    
    @Test func testChatRequestDecoding() throws {
        let decoder = JSONDecoder()
        
        let jsonStringWithLevel = """
        {
            "model": "deepseek-r1",
            "messages": [{"role": "user", "content": "Hi"}],
            "stream": true,
            "think": "high"
        }
        """
        let reqWithLevel = try decoder.decode(ChatRequest.self, from: jsonStringWithLevel.data(using: .utf8)!)
        #expect(reqWithLevel.think == .string("high"))
        
        let jsonStringWithBool = """
        {
            "model": "deepseek-r1",
            "messages": [{"role": "user", "content": "Hi"}],
            "stream": true,
            "think": false
        }
        """
        let reqWithBool = try decoder.decode(ChatRequest.self, from: jsonStringWithBool.data(using: .utf8)!)
        #expect(reqWithBool.think == .bool(false))
    }
}
