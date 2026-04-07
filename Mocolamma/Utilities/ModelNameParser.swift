import Foundation

/// ユーザーが入力した文字列からOllamaのモデル名を抽出するためのユーティリティです。
/// 「ollama run modelname」のようなフルコマンドが入力された場合でも、モデル名のみを取り出すことができます。
struct ModelNameParser {
    /// 入力文字列からモデル名を抽出します。
    /// - Parameter input: ユーザーが入力した文字列。
    /// - Returns: 抽出されたモデル名。抽出できない場合はトリミングされた入力文字列をそのまま返します。
    static func parse(input: String) -> String {
        // 前後の空白と改行をトリミング
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // ollamaコマンドが含まれているかチェック (大文字小文字を区別しない)
        let lowercased = trimmed.lowercased()
        if lowercased.contains("ollama") {
            // 正規表現でモデル名を抽出
            // ollama (run|pull|show|push|cp|rm) の後に続く、英数字、ドット、ハイフン、アンダースコア、コロンの組み合わせを抽出
            let pattern = #"(?i)ollama\s+(?:run|pull|show|push|cp|rm)\s+([a-zA-Z0-9.\-_:/]+)"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) {
                if let range = Range(match.range(at: 1), in: trimmed) {
                    let extracted = String(trimmed[range])
                    print("ModelNameParser: Extracted '\(extracted)' from '\(trimmed)'")
                    return extracted
                }
            }
        }
        
        // ollamaコマンドが含まれていない、または抽出に失敗した場合はトリミングした値をそのまま返す
        return trimmed
    }
}
