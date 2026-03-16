import Testing
import Foundation
@testable import Mocolamma

struct ModelNameParserTests {

    @Test func testStandardModelName() {
        #expect(ModelNameParser.parse(input: "qwen3.5:0.8b") == "qwen3.5:0.8b")
        #expect(ModelNameParser.parse(input: "llama3") == "llama3")
    }

    @Test func testOllamaRunCommand() {
        #expect(ModelNameParser.parse(input: "ollama run qwen3.5:0.8b") == "qwen3.5:0.8b")
        #expect(ModelNameParser.parse(input: "OLLAMA RUN llama3") == "llama3")
    }

    @Test func testOllamaPullCommand() {
        #expect(ModelNameParser.parse(input: "ollama pull gemma:2b") == "gemma:2b")
    }

    @Test func testOllamaShowCommand() {
        #expect(ModelNameParser.parse(input: "ollama show phi3") == "phi3")
    }

    @Test func testTrimming() {
        #expect(ModelNameParser.parse(input: "  ollama run gemma:2b  ") == "gemma:2b")
        #expect(ModelNameParser.parse(input: "\nollama pull llama3\n") == "llama3")
    }
    
    @Test func testNoMatchFallback() {
        // ollamaは含まれるが、コマンド形式になっていない場合はそのまま返す
        #expect(ModelNameParser.parse(input: "ollama help") == "ollama help")
        #expect(ModelNameParser.parse(input: "my-ollama-model") == "my-ollama-model")
    }
}
