import SwiftUI

// MARK: - モデルインスペクター詳細ビューヘルパー
struct ModelInspectorDetailView: View {
    let model: OllamaModel
    @EnvironmentObject var commandExecutor: CommandExecutor
    
    @State private var modelInfo: [String: JSONValue]?
    @State private var licenseBody: String?
    @State private var licenseLink: String?
    @State private var isLoadingInfo: Bool = false
    @State private var fetchedCapabilities: [String]?
    
    var body: some View {
        ModelInspectorView(
            model: model,
            modelInfo: modelInfo,
            isLoading: isLoadingInfo,
            fetchedCapabilities: fetchedCapabilities,
            licenseBody: licenseBody,
            licenseLink: licenseLink
        )
        .onAppear(perform: loadModelInfo)
    }
    
    private func loadModelInfo() {
        isLoadingInfo = true
        Task {
            let fetchedResponse = await commandExecutor.fetchModelInfo(modelName: model.name)
            await MainActor.run {
                self.modelInfo = fetchedResponse?.model_info
                self.licenseBody = fetchedResponse?.license
                // デモモデルの場合はテスト用ライセンスURLを設定
                if model.name == "demo:0b" || model.name == "demo2:0b" {
                    self.licenseLink = "https://example.com/"
                } else {
                    // 通常のモデルでは、model_infoからライセンスリンクを取得
                    self.licenseLink = fetchedResponse?.model_info?["general.license.link"]?.stringValue
                }
                self.fetchedCapabilities = fetchedResponse?.capabilities
                self.isLoadingInfo = false
            }
        }
    }
}
