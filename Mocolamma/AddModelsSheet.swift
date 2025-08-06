import SwiftUI

// MARK: - モデル追加シート

/// 新しいモデルの追加（プル）を行うためのシートビューです。ユーザーがモデル名を入力し、ダウンロードを開始するためのUIを提供します。
struct AddModelsSheet: View {
    @Binding var showingAddSheet: Bool // シートの表示/非表示を制御するバインディング
    @ObservedObject var executor: CommandExecutor // CommandExecutorのインスタンスを受け取ります
    
    @State private var modelNameInput: String = "" // モデル名入力
    @State private var showHttpErrorAlert: Bool = false
    @State private var httpErrorMessage: String = ""
    @State private var pullErrorTriggeredSeen: Bool = false
    
    var body: some View {        VStack(alignment: .leading, spacing: 20) {
        Text("Add Model") // モデル追加シートのタイトル。
            .font(.title)
            .bold()
        
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter the name of the model you want to add.") // モデル追加シートの説明。
                .font(.headline)
            
            TextField("e.g., gemma3:4b, phi4:latest", text: $modelNameInput) // モデル追加入力フィールドのプレースホルダーテキスト。
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Spacer()
            
            HStack {
                Spacer()
                Button("Cancel") { // キャンセルボタンのテキスト。
                    showingAddSheet = false
                }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction) // Escキーでキャンセル
                
                Button("Add") { // 追加ボタンのテキスト。
                    if !modelNameInput.isEmpty {
                        let name = modelNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        executor.pullHttpErrorTriggered = false
                        executor.pullHttpErrorMessage = ""
                        executor.pullModel(modelName: name)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            if !executor.pullHttpErrorTriggered {
                                showingAddSheet = false
                            }
                        }
                    }
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction) // Enterキーで実行
                .disabled(modelNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || executor.isPulling)
            }
        }
    }
    .padding()
    .frame(width: 350, height: 180) // シートの固定サイズ
    .onReceive(executor.$pullHttpErrorTriggered) { triggered in
        if triggered && !pullErrorTriggeredSeen {
            httpErrorMessage = executor.pullHttpErrorMessage
            showHttpErrorAlert = true
            pullErrorTriggeredSeen = true
        }
    }
    .onChange(of: showHttpErrorAlert) { _, shown in
        if shown == false {
            pullErrorTriggeredSeen = false
            executor.pullHttpErrorTriggered = false
            executor.pullHttpErrorMessage = ""
        }
    }
        
    .alert("Model Pull Error", isPresented: $showHttpErrorAlert) {
        Button("OK") { showHttpErrorAlert = false }
    } message: {
        Text(httpErrorMessage)
    }}
}

// MARK: - プレビュー用

#Preview {
    // プレビュー用にダミーのServerManagerとCommandExecutorインスタンスを作成
    let previewServerManager = ServerManager()
    let previewCommandExecutor = CommandExecutor(serverManager: previewServerManager)
    
    return AddModelsSheet(showingAddSheet: .constant(true), executor: previewCommandExecutor)
}
