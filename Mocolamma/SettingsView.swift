import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack {
            Image(systemName: "gearshape.fill") // 歯車アイコン
                .font(.largeTitle)
                .padding(.bottom, 10)

            Text("Settings") // 設定
                .font(.title)
                .bold()
                .padding(.bottom, 5)

            Text("Settings content will go here.") // 設定のコンテンツはここに表示されます。
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // 全体に広がるように設定
        .navigationTitle("Settings") // ナビゲーションタイトル: 設定。
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
