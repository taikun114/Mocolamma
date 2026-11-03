import SwiftUI

// MARK: - モデルインスペクター詳細ビューヘルパー
struct ModelInspectorDetailView: View {
    let model: OllamaModel
    @Binding var selectedFilterTag: String?
    @Environment(CommandExecutor.self) var commandExecutor
    
    @State private var response: OllamaShowResponse?
    @State private var isLoadingInfo: Bool = false
    
    // commandExecutor.models から最新のモデル情報を取得するための計算プロパティ
    private var latestModel: OllamaModel {
        // modelsByID を使用して O(1) で検索
        commandExecutor.modelsByID[model.id] ?? model
    }
    
    var body: some View {
        ModelInspectorView(
            model: latestModel,
            response: response,
            isLoading: isLoadingInfo,
            selectedFilterTag: $selectedFilterTag
        )
        .task(id: ModelDetailRequest(context: commandExecutor.modelRequestContext, modelName: model.name, cacheRevision: commandExecutor.modelInfoCacheRevision)) {
            await loadModelInfo()
        }
    }
    
    private func loadModelInfo() async {
        let context = commandExecutor.modelRequestContext
        response = nil
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
        let fetchedResponse = await commandExecutor.fetchModelInfo(modelName: model.name, context: context)
        guard !Task.isCancelled, context == commandExecutor.modelRequestContext else { return }
        applyResponse(fetchedResponse)
    }
    
    private func applyResponse(_ fetchedResponse: OllamaShowResponse?) {
#if os(visionOS)
        withAnimation(.easeInOut(duration: 0.3)) {
            self.response = fetchedResponse
            self.isLoadingInfo = false
        }
#else
        self.response = fetchedResponse
        self.isLoadingInfo = false
#endif
    }
}
