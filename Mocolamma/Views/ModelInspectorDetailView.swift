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
            self.response = fetchedResponse
            self.isLoadingInfo = false
        }
#else
        self.response = fetchedResponse
        self.isLoadingInfo = false
#endif
    }
}
