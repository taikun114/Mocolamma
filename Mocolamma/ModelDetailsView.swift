import SwiftUI
import AppKit // NSPasteboard のため

// MARK: - モデル詳細ビュー

/// 選択されたOllamaモデルの詳細情報を表示するSwiftUIビューです。
struct ModelDetailsView: View {
    let model: OllamaModel
    let modelInfo: [String: JSONValue]? // 追加
    let isLoading: Bool // 追加
    let fetchedCapabilities: [String]? // 追加
    let licenseBody: String? // 新しく追加: ライセンス本文
    let licenseLink: String? // 新しく追加: ライセンスリンク

    @State private var showingLicenseSheet = false // 新しく追加: ライセンスシート表示制御

    // サイズのフルバイト表記を取得するヘルパー
    private var fullSizeText: String {
        return "\(model.size)"
    }

    // サイズのツールチップ用テキスト（読みやすいサイズ + フルサイズ表記）
    private var sizeTooltipText: String {
        return "\(model.formattedSize)、\(model.size) B"
    }
    
    // modelInfoからパラメーターカウントを取得するヘルパー
    private var parameterCount: (formatted: String, raw: Int)? {
        guard let count = modelInfo?["general.parameter_count"]?.intValue else { return nil }
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.maximumFractionDigits = 0 // 小数点以下を表示しない
        let formattedCount = numberFormatter.string(from: NSNumber(value: count)) ?? String(count)
        return (formattedCount, count)
    }

    // modelInfoからコンテキスト長を取得するヘルパー
    private var contextLength: (formatted: String, raw: Int)? {
        guard let info = modelInfo else { return nil }
        // ".context_length"で終わるキーを探す
        if let key = info.keys.first(where: { $0.hasSuffix(".context_length") }) {
            guard let length = info[key]?.intValue else { return nil }
            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            numberFormatter.maximumFractionDigits = 0 // 小数点以下を表示しない
            let formattedLength = numberFormatter.string(from: NSNumber(value: length)) ?? String(length)
            return (formattedLength, length)
        }
        return nil
    }

    // modelInfoからエンベディング長を取得するヘルper
    private var embeddingLength: (formatted: String, raw: Int)? {
        guard let info = modelInfo else { return nil }
        // ".embedding_length"で終わるキーを探す
        if let key = info.keys.first(where: { $0.hasSuffix(".embedding_length") }) {
            guard let length = info[key]?.intValue else { return nil }
            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            numberFormatter.maximumFractionDigits = 0 // 小数点以下を表示しない
            let formattedLength = numberFormatter.string(from: NSNumber(value: length)) ?? String(length)
            return (formattedLength, length)
        }
        return nil
    }

    // 新しく追加: general.license を取得するヘルパー
    private var licenseName: String {
        let rawLicense = modelInfo?["general.license"]?.stringValue ?? "Other"
        switch rawLicense.lowercased() {
        case "mit":
            return "MIT License"
        case "apache-2.0":
            return "Apache License 2.0"
        default:
            return rawLicense
        }
    }

    // MARK: - ヘルパー関数

    private func tagView(for capability: String) -> some View {
        let displayText: String
        let iconName: String
        switch capability.lowercased() {
        case "completion":
            displayText = String(localized: "Completion")
            iconName = "character.cursor.ibeam"
        case "vision":
            displayText = String(localized: "Vision")
            iconName = "eye"
        case "tools":
            displayText = String(localized: "Tools")
            iconName = "wrench.and.screwdriver"
        default:
            displayText = capability
            iconName = "tag"
        }
        return HStack(spacing: 4) {
            Image(systemName: iconName)
            Text(displayText)
        }
        .font(.caption)
        .bold()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
        .foregroundColor(.accentColor)
    }

    var body: some View {
        ScrollView { // ScrollViewを追加
            VStack(alignment: .leading, spacing: 10) {
                // タイトルをモデルの名前に変更
                Text(model.name) // モデル詳細のタイトルをモデル名に変更。
                    .font(.title2)
                    .bold()
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Capabilities Section
                if let capabilities = fetchedCapabilities, !capabilities.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(capabilities, id: \.self) { capability in
                                tagView(for: capability)
                            }
                        }
                        
                    }
                }

                Divider()

                Group {
                    VStack(alignment: .leading) {
                        Text("Model Name:") // モデル名。
                        Text(model.model)
                            .font(.title3) // フォントサイズを大きく、太字に
                            .bold()
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(model.model) // ツールチップにフルテキストを表示
                            .contextMenu {
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(model.model, forType: .string)
                                }
                            }
                    }
                    VStack(alignment: .leading) {
                        Text("Size:") // サイズ。
                        Text(model.formattedSize)
                            .font(.title3) // フォントサイズを大きく、太字に
                            .bold()
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(sizeTooltipText) // 読みやすいサイズ + フルサイズ表記をツールチップに表示
                            .contextMenu {
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(fullSizeText, forType: .string) // フルサイズ表記のみをコピー
                                }
                            }
                    }
                    VStack(alignment: .leading) {
                        Text("Modified At:") // 変更日。
                        Text(model.formattedModifiedAt)
                            .font(.title3) // フォントサイズを大きく、太字に
                            .bold()
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(model.formattedModifiedAt) // ツールチップにフルテキストを表示
                            .contextMenu {
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(model.formattedModifiedAt, forType: .string)
                                }
                            }
                    }
                    VStack(alignment: .leading) {
                        Text("Digest:") // ダイジェスト。
                        Text(model.digest)
                            .font(.title3) // フォントサイズを大きく、太字に
                            .bold()
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(model.digest) // ツールチップにフルテキストを表示
                            .contextMenu {
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(model.digest, forType: .string)
                                }
                            }
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
                                    .help(parentModel) // ツールチップにフルテキストを表示
                                    .contextMenu {
                                        Button("Copy") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(parentModel, forType: .string)
                                        }
                                    }
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
                                    .help(format) // ツールチップにフルテキストを表示
                                    .contextMenu {
                                        Button("Copy") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(format, forType: .string)
                                        }
                                    }
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
                                    .help(family) // ツールチップにフルテキストを表示
                                    .contextMenu {
                                        Button("Copy") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(family, forType: .string)
                                        }
                                    }
                            }
                        }
                        if let families = details.families, !families.isEmpty {
                            VStack(alignment: .leading) {
                                Text("Families:") // ファミリーズ。
                                let familiesText = families.joined(separator: ", ")
                                Text(familiesText)
                                    .font(.title3) // フォントサイズを大きく、太字に
                                    .bold()
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .help(familiesText) // ツールチップにフルテキストを表示
                                    .contextMenu {
                                        Button("Copy") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(familiesText, forType: .string)
                                        }
                                    }
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
                                    .help(parameterSize) // ツールチップにフルテキストを表示
                                    .contextMenu {
                                        Button("Copy") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(parameterSize, forType: .string)
                                        }
                                    }
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
                                    .help(quantizationLevel) // ツールチップにフルテキストを表示
                                    .contextMenu {
                                        Button("Copy") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(quantizationLevel, forType: .string)
                                        }
                                    }
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
                
                Divider()

                Text("Model Information:") // モデル情報セクションのタイトル
                    .font(.headline)

                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.5, anchor: .center)
                        Text("Loading model info...") // モデル情報を読み込み中...
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if modelInfo != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        // 新しく追加: ライセンス
                        VStack(alignment: .leading) {
                            Text("License:") // ライセンス
                            if licenseBody != nil {
                                Button(action: {
                                    showingLicenseSheet = true
                                }) {
                                    Text(licenseName)
                                        .font(.title3).bold()
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(PlainButtonStyle())
                            } else {
                                Text(licenseName)
                                    .font(.title3).bold()
                            }
                        }
                        
                        // パラメーターカウント
                        if let count = parameterCount {
                            VStack(alignment: .leading) {
                                Text("Parameter Count:") // パラメーターカウント
                                Text(count.formatted)
                                    .font(.title3).bold()
                                    .contextMenu {
                                        Button("Copy") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(String(count.raw), forType: .string)
                                        }
                                    }
                            }
                        }
                        // コンテキストレングス
                        if let length = contextLength {
                            VStack(alignment: .leading) {
                                Text("Context Length:") // コンテキスト長
                                Text(length.formatted)
                                    .font(.title3).bold()
                                    .contextMenu {
                                        Button("Copy") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(String(length.raw), forType: .string)
                                        }
                                    }
                            }
                        }
                        // エンベディング長
                        if let length = embeddingLength {
                            VStack(alignment: .leading) {
                                Text("Embedding Length:") // エンベディング長
                                Text(length.formatted)
                                    .font(.title3).bold()
                                    .contextMenu {
                                        Button("Copy") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(String(length.raw), forType: .string)
                                        }
                                    }
                            }
                        }
                        
                        // もし情報が一つもなければ
                        if parameterCount == nil && contextLength == nil && embeddingLength == nil && licenseBody == nil {
                             Text("No model information available.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Could not load model information.") // モデル情報を読み込めませんでした。
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding() // ここにパディングを追加
        }
        .sheet(isPresented: $showingLicenseSheet) {
            if let licenseBody = licenseBody {
                LicenseTextView(licenseText: licenseBody, licenseLink: licenseLink)
            }
        }
    }
}
