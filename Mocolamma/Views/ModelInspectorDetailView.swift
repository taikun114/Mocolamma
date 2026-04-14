import SwiftUI

// MARK: - モデルインスペクター詳細ビューヘルパー
struct ModelInspectorDetailView: View {
    let model: OllamaModel
    @Binding var selectedFilterTag: String?
    @Environment(CommandExecutor.self) var commandExecutor
    
    @State private var modelInfo: [String: JSONValue]?
    @State private var licenseBody: String?
    @State private var licenseLink: String?
    @State private var isLoadingInfo: Bool = false
    @State private var fetchedCapabilities: [String]?
    
    // commandExecutor.models から最新のモデル情報を取得するための計算プロパティ
    private var latestModel: OllamaModel {
        commandExecutor.models.first(where: { $0.id == model.id }) ?? model
    }
    
    var body: some View {
        ModelInspectorView(
            model: latestModel,
            modelInfo: modelInfo,
            isLoading: isLoadingInfo,
            fetchedCapabilities: fetchedCapabilities,
            licenseBody: licenseBody,
            licenseLink: licenseLink,
            selectedFilterTag: $selectedFilterTag
        )
        .onAppear(perform: loadModelInfo)
        .onChange(of: model.id) { _, _ in
            loadModelInfo()
        }
    }
    
    private func loadModelInfo() {
        // すでにキャッシュがある場合はそれを使用
        if let cached = commandExecutor.getCachedModelInfo(modelName: model.name) {
            applyResponse(cached)
            return
        }

#if os(visionOS)
        withAnimation(.easeInOut(duration: 0.3)) {
            isLoadingInfo = true
        }
#else
        isLoadingInfo = true
#endif
        Task {
            let fetchedResponse = await commandExecutor.fetchModelInfo(modelName: model.name)
            await MainActor.run {
                applyResponse(fetchedResponse)
            }
        }
    }
    
    private func applyResponse(_ fetchedResponse: OllamaShowResponse?) {
#if os(visionOS)
        withAnimation(.easeInOut(duration: 0.3)) {
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
#else
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
#endif
    }
}
