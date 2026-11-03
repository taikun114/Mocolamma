import Testing
@testable import Mocolamma

struct ScreenshotConfigurationTests {
    @Test(arguments: ["ja-JP", "en-US"])
    func decisionPresetsContainValidOrderedConditions(language: String) {
        let preset = ScreenshotConfiguration.decisionPreset(language: language)
        #expect(ScreenshotConfiguration.decisionModelName == "d3:4b")
        #expect(!preset.input.isEmpty)
        #expect(preset.conditions.map(\.kind) == [.choice, .noul, .score])
        #expect(preset.conditions.allSatisfy { $0.isValid })
        #expect(preset.conditions[0].validOptions.count == 3)
        #expect(preset.conditions[2].validOptions.count == 5)
        #expect(Set(preset.conditions.map(\.id)).count == 3)
        if language.hasPrefix("en") {
            #expect(preset.input.contains("crashes"))
            #expect(preset.conditions[2].validOptions.first == "Minor")
            #expect(preset.conditions[2].validOptions.last == "Critical")
        } else {
            #expect(preset.input.contains("クラッシュ"))
            #expect(preset.conditions[2].validOptions.first == "軽微")
            #expect(preset.conditions[2].validOptions.last == "重大")
        }
    }
}
