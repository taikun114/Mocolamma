import SwiftUI

// MARK: - モデル詳細ビュー

/// 選択されたOllamaモデルの詳細情報を表示するSwiftUIビューです。
struct ModelDetailsView: View { // 構造体名 ModelDetailsView はそのまま
    let model: OllamaModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // タイトルをモデルの名前に変更
            Text(model.name) // モデル詳細のタイトルをモデル名に変更。
                .font(.title2)
                .bold()
                .padding(.bottom, 5)

            Divider()

            Group {
                VStack(alignment: .leading) {
                    Text("Model Name:") // モデル名。
                    Text(model.model)
                        .font(.title3) // フォントサイズを大きく、太字に
                        .bold()
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                VStack(alignment: .leading) {
                    Text("Size:") // サイズ。
                    Text(model.formattedSize)
                        .font(.title3) // フォントサイズを大きく、太字に
                        .bold()
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                VStack(alignment: .leading) {
                    Text("Modified At:") // 変更日。
                    Text(model.formattedModifiedAt)
                        .font(.title3) // フォントサイズを大きく、太字に
                        .bold()
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                VStack(alignment: .leading) {
                    Text("Digest:") // ダイジェスト。
                    Text(model.digest)
                        .font(.title3) // フォントサイズを大きく、太字に
                        .bold()
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.body) // ラベルのフォントサイズは維持
            .frame(maxWidth: .infinity, alignment: .leading) // 内側のパディングをなくす

            Divider()

            Text("Details Information:") // 詳細情報（Details）。
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading) // 内側のパディングをなくす

            if let details = model.details { // ここでOptionalをアンラップします
                VStack(alignment: .leading, spacing: 10) { // 各VStackの間にスペースを追加
                    if let parentModel = details.parent_model, !parentModel.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Parent Model:") // 親モデル。
                            Text(parentModel)
                                .font(.title3) // フォントサイズを大きく、太字に
                                .bold()
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    if let format = details.format {
                        VStack(alignment: .leading) {
                            Text("Format:") // フォーマット。
                            Text(format)
                                .font(.title3) // フォントサイズを大きく、太字に
                                .bold()
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    if let family = details.family {
                        VStack(alignment: .leading) {
                            Text("Family:") // ファミリー。
                            Text(family)
                                .font(.title3) // フォントサイズを大きく、太字に
                                .bold()
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    if let families = details.families, !families.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Families:") // ファミリーズ。
                            Text(families.joined(separator: ", "))
                                .font(.title3) // フォントサイズを大きく、太字に
                                .bold()
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    if let parameterSize = details.parameter_size {
                        VStack(alignment: .leading) {
                            Text("Parameter Size:") // パラメータサイズ。
                            Text(parameterSize)
                                .font(.title3) // フォントサイズを大きく、太字に
                                .bold()
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    if let quantizationLevel = details.quantization_level {
                        VStack(alignment: .leading) {
                            Text("Quantization Level:") // 量子化レベル。
                            Text(quantizationLevel)
                                .font(.title3) // フォントサイズを大きく、太字に
                                .bold()
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .font(.subheadline) // ラベルのフォントサイズは維持
                .frame(maxWidth: .infinity, alignment: .leading) // 内側のパディングをなくす
            } else {
                Text("No details available.") // 詳細情報はありません。
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading) // 内側のパディングをなくす
            }
            
            Spacer()
        }
        .padding() // 全体のパディング
    }
}
