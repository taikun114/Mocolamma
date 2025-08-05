import SwiftUI

// MARK: - モデル追加シート

/// 新しいモデルの追加（プル）を行うためのシートビューです。ユーザーがモデル名を入力し、ダウンロードを開始するためのUIを提供します。
struct AddModelsSheet: View {
    @Binding var showingAddSheet: Bool // シートの表示/非表示を制御するバインディング
    @ObservedObject var executor: CommandExecutor // CommandExecutorのインスタンスを受け取ります

    @State private var modelNameInput: String = "" // モデル名入力

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
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
                            executor.pullModel(modelName: modelNameInput.trimmingCharacters(in: .whitespacesAndNewlines))
                            showingAddSheet = false // シートを閉じます
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
    }
}

// MARK: - プレビュー用

#Preview {
    // プレビュー用にダミーのServerManagerとCommandExecutorインスタンスを作成
    let previewServerManager = ServerManager()
    let previewCommandExecutor = CommandExecutor(serverManager: previewServerManager)
    
    return AddModelsSheet(showingAddSheet: .constant(true), executor: previewCommandExecutor)
}
