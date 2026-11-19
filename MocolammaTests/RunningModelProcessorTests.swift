import Foundation
import Testing
@testable import Mocolamma

struct RunningModelProcessorTests {
    @Test func decodesLoadedModelDetails() throws {
        let json = #"{"name":"example:small","runner":"llama","context_length":8192}"#
        let model = try JSONDecoder().decode(OllamaRunningModel.self, from: Data(json.utf8))
        #expect(model.executionBackend == "llama")
        #expect(model.contextLength == 8192)
    }

    @Test(arguments: [
        #"{"name":"example:small"}"#,
        #"{"name":"example:small","runner":null,"context_length":null}"#,
        #"{"name":"example:small","runner":"  ","context_length":"unavailable"}"#
    ])
    func missingDetailsDoNotPreventDecoding(json: String) throws {
        let model = try JSONDecoder().decode(OllamaRunningModel.self, from: Data(json.utf8))
        #expect(model.executionBackend == nil)
        #expect(model.contextLength == nil)
    }

    @Test(arguments: [
        (Int64(1000), Int64(0), "CPU 100%"),
        (1000, 1000, "GPU 100%"),
        (1000, 750, "CPU 25% · GPU 75%"),
        (1000, 666, "CPU 33% · GPU 67%"),
        (1000, 999, "GPU 100%"),
        (1000, 1, "CPU 100%")
    ])
    func displaysAllocationWithoutZeroPercent(size: Int64, vram: Int64, expected: String) throws {
        let json = "{\"name\":\"example:small\",\"size\":\(size),\"size_vram\":\(vram)}"
        let model = try JSONDecoder().decode(OllamaRunningModel.self, from: Data(json.utf8))
        #expect(model.processorDistribution == expected)
    }

    @Test(arguments: [
        "{\"name\":\"example:small\"}",
        "{\"name\":\"example:small\",\"size\":1000}",
        "{\"name\":\"example:small\",\"size_vram\":0}",
        "{\"name\":\"example:small\",\"size\":0,\"size_vram\":0}",
        "{\"name\":\"example:small\",\"size\":100,\"size_vram\":101}",
        "{\"name\":\"example:small\",\"size\":100,\"size_vram\":-1}"
    ])
    func omitsUnavailableOrInvalidAllocation(json: String) throws {
        let model = try JSONDecoder().decode(OllamaRunningModel.self, from: Data(json.utf8))
        #expect(model.processorDistribution == nil)
    }
}
