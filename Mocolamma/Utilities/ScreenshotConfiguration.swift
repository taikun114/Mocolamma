import Foundation

enum ScreenshotConfiguration {
    static var chatPrompt: String {
        Locale.preferredLanguages.first?.hasPrefix("en") == true
            ? "Hello. Please tell me one thing you are good at."
            : "こんにちは。あなたが得意なことを1つ教えてください。"
    }

    static var isEnabled: Bool {
#if DEBUG && targetEnvironment(simulator)
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
