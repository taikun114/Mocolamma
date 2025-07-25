import SwiftUI

// MARK: - モデル追加シート

struct AddModelsSheet: View {
    @Binding var showingAddSheet: Bool
    @ObservedObject var executor: CommandExecutor
    @State private var modelNameInput: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Model") // モデル追加シートのタイトル。
                .font(.title)
                .bold()

            Text("Enter the name of the model you want to add.") // モデル追加シートの説明。
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            TextField("e.g., gemma3:4b, phi4:latest", text: $modelNameInput) // モデル追加入力フィールドのプレースホルダーテキスト。
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            HStack {
                Button("Cancel") { // キャンセルボタンのテキスト。
                    showingAddSheet = false
                }
                .keyboardShortcut(.cancelAction) // Escキーでキャンセル
                
                Button("Add") { // 追加ボタンのテキスト。
                    if !modelNameInput.isEmpty {
                        executor.pullModel(modelName: modelNameInput.trimmingCharacters(in: .whitespacesAndNewlines))
                        showingAddSheet = false // シートを閉じます
                    }
                }
                .keyboardShortcut(.defaultAction) // Enterキーで実行
                .disabled(modelNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || executor.isPulling)
            }
        }
        .padding(30)
        .frame(minWidth: 400, minHeight: 250) // シートの最小サイズ
    }
}

struct AddModelsSheet_Previews: PreviewProvider {
    @State static var showingAddSheet = true
    static var previews: some View {
        AddModelsSheet(showingAddSheet: $showingAddSheet, executor: CommandExecutor())
    }
}
