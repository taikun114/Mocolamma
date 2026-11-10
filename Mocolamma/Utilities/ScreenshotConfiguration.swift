import Foundation

enum ScreenshotConfiguration {
    static var chatPrompt: String {
        Locale.preferredLanguages.first?.hasPrefix("ja") == true
            ? "こんにちは。あなたが得意なことを1つ教えてください。"
            : "Hello. Please tell me one thing you are good at."
    }

    static let decisionModelName = "d3:4b"

    static let speechModelName = "lfm3-audio:2b"

    static var speechPrompt: String {
        speechPrompt(language: Locale.preferredLanguages.first ?? "en")
    }

    static func speechPrompt(language: String) -> String {
        if !language.hasPrefix("ja") {
            return """
            Mocolamma is an application that connects to Ollama servers, allowing you to manage models, chat, generate images, and more.

            Mocolamma supports macOS, iOS, iPadOS, and visionOS, so you can use it on a wide range of devices. Even if your Mac with Ollama installed is in another room, you can conveniently control it remotely from your iPhone or another device at hand.
            """
        }
        return """
        Mocolammaは、Ollamaサーバーと接続してモデルを管理したり、チャットや画像生成などを行ったりすることができるアプリケーションです。

        MocolammaはmacOS、iOS、iPadOS、visionOSに対応しており、幅広いデバイスでご利用いただけます。OllamaがインストールされたMacが別の部屋にあっても、手元のiPhoneなどからリモートで操作することができるため、非常に便利です。
        """
    }

    struct DecisionPreset {
        let input: String
        let conditions: [DecisionCondition]
    }

    static var decisionPreset: DecisionPreset {
        decisionPreset(language: Locale.preferredLanguages.first ?? "en")
    }

    static func decisionPreset(language: String) -> DecisionPreset {
        if !language.hasPrefix("ja") {
            return DecisionPreset(
                input: "The app suddenly crashes a few seconds after launch. Reinstalling it does not help, and it worked without any issues in the previous version. The app is currently completely unusable.",
                conditions: [
                    DecisionCondition(instructions: "Classify this report.", options: ["Bug report", "Feature request", "Suggestion"]),
                    DecisionCondition(instructions: "Is this a report about a crash?", kind: .noul),
                    DecisionCondition(instructions: "Evaluate the severity of this issue.", kind: .score, options: ["Minor", "Low", "Medium", "High", "Critical"])
                ]
            )
        }
        return DecisionPreset(
            input: "アプリを起動すると、数秒後に突然クラッシュしてしまいます。再インストールしても改善せず、以前のバージョンでは問題なく動作していました。現在、アプリをまったく使用できない状態です。",
            conditions: [
                DecisionCondition(instructions: "この報告を分類してください。", options: ["バグ報告", "新機能の要望", "提案"]),
                DecisionCondition(instructions: "これはクラッシュに関する報告ですか？", kind: .noul),
                DecisionCondition(instructions: "この問題の深刻度を評価してください。", kind: .score, options: ["軽微", "低", "中", "高", "重大"])
            ]
        )
    }

    static var isEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ScreenshotMode")
#else
        false
#endif
    }

    static func configure(_ serverManager: ServerManager) {
        guard isEnabled else { return }
        let servers = [
            ServerInfo(name: "Mac mini (2024)", host: "192.168.1.57:11434", iconName: "macmini.gen3"),
            ServerInfo(name: "Mac mini M6", host: "192.168.1.59:11434", iconName: "macmini.gen3")
        ]
        serverManager.servers = servers
        serverManager.selectedServerID = servers.last?.id
    }

    @MainActor
    static func loadImage(into executor: CommandExecutor) {
        guard isEnabled else { return }
        guard let url = Bundle.main.url(forResource: "screenshot-apple", withExtension: "png") else {
            print("Screenshot image is missing from the app bundle.")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let createdAt = MessageView.iso8601Formatter.string(from: Date())
            executor.imageMessages = [
                ChatMessage(role: "user", content: "Apple", createdAt: createdAt),
                ChatMessage(role: "assistant", content: "", createdAt: createdAt,
                            generatedImage: data.base64EncodedString(), isImageGeneration: true)
            ]
            print("Screenshot image loaded from the app bundle.")
        } catch {
            print("Failed to load screenshot image: \(error)")
        }
    }
}
