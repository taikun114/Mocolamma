import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - モデル詳細ビュー

/// 選択されたOllamaモデルの詳細情報を表示するSwiftUIビューです。
struct ModelInspectorView: View {
    let model: OllamaModel
    let response: OllamaShowResponse?
    let isLoading: Bool
    @Binding var selectedFilterTag: String?
    
    @State private var showingLicenseSheet = false
    
    // タグエリアのドラッグスクロール用状態変数
    @State private var tagsScrollPos: ScrollPosition = .init(point: .zero)
    @State private var currentTagsOffset: CGPoint = .zero
    @State private var dragStartOffset: CGPoint = .zero
    @State private var isDraggingTags = false
    
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
        guard let count = response?.parameterCount else { return nil }
        return (OllamaModel.formatDecimal(count), count)
    }
    
    // modelInfoからコンテキスト長を取得するヘルパー
    private var contextLength: (formatted: String, raw: Int)? {
        guard let length = response?.contextLength else { return nil }
        return (OllamaModel.formatDecimal(length), length)
    }
    
    // modelInfoからエンベディング長を取得するヘルパー
    private var embeddingLength: (formatted: String, raw: Int)? {
        guard let length = response?.embeddingLength else { return nil }
        return (OllamaModel.formatDecimal(length), length)
    }
    
    
    private var licenseBody: String? {
        response?.license
    }
    
    private var licenseLink: String? {
        // デモモデルの場合はテスト用ライセンスURLを設定
        if model.name == "demo:0b" || model.name == "demo2:0b" {
            return "https://example.com/"
        }
        return response?.model_info?["general.license.link"]?.stringValue
    }
    
    private var licenseName: String {
        // 1. model_infoに明示的なライセンス名がある場合
        if let rawLicense = response?.model_info?["general.license"]?.stringValue {
            switch rawLicense.lowercased() {
            case "mit":
                return "MIT License"
            case "apache-2.0":
                return "Apache License 2.0"
            default:
                return rawLicense
            }
        }
        
        // 2. ライセンス名がないが本文がある場合、本文から推測
        if let body = licenseBody {
            if body.contains("MIT License") {
                return "MIT License"
            }
            if body.contains("Apache License") && body.contains("Version 2.0") {
                return "Apache License 2.0"
            }
        }
        
        return String(localized: "Other License")
    }
    
    // MARK: - ヘルパー関数
    
    private func tagView(for capability: String) -> some View {
        let displayText: String
        let iconName: String
        let isSelected = selectedFilterTag == capability
        
        switch capability.lowercased() {
        case "completion":
            displayText = String(localized: "Completion")
            iconName = "character.cursor.ibeam"
        case "vision":
            displayText = String(localized: "Vision")
            iconName = "eye"
        case "audio":
            displayText = String(localized: "Audio")
            iconName = "music.note"
        case "tools":
            displayText = String(localized: "Tools")
            iconName = "wrench.and.screwdriver"
        case "thinking":
            displayText = String(localized: "Thinking")
            iconName = "brain.filled.head.profile"
        case "embedding":
            displayText = String(localized: "Embedding")
            iconName = "square.stack.3d.up"
        case "image":
            displayText = String(localized: "Image")
            iconName = "photo"
        default:
            displayText = capability
            iconName = "tag"
        }
        
        return Button(action: {
            if selectedFilterTag == capability {
                selectedFilterTag = nil
            } else {
                selectedFilterTag = capability
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                Text(displayText)
            }
            .font(.caption)
            .bold()
            .contentShape(Capsule()) // 点击判定范围
#if !os(macOS)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
#else
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
#endif
#if os(visionOS)
            .background(Capsule().fill(Color.accentColor))
            .foregroundColor(.white)
            .overlay(
                Capsule()
                    .stroke(Color.white, lineWidth: isSelected ? 2 : 0)
            )
#else
            .background(Capsule().fill(Color.accentColor.opacity(isSelected ? 0.3 : 0.2)))
            .foregroundColor(.accentColor)
            .overlay(
                Capsule()
                    .stroke(Color.accentColor, lineWidth: isSelected ? 2 : 0)
            )
#endif
        }
        .buttonStyle(.plain)
        .onHover { inside in
#if os(macOS)
            if inside && !isDraggingTags {
                NSCursor.pointingHand.push()
            } else if !inside && !isDraggingTags {
                // ドラッグ中ではない場合のみ抜けた時にpop
                NSCursor.pop()
            }
#endif
        }
    }
    
    var body: some View {
        let copyIconName = SFSymbol.copy
        
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.name)
                    .font(.title2)
                    .bold()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(model.name) // モデル名のフルテキストをツールチップに表示
                
                // 機能セクション
                if let capabilities = response?.capabilities, !capabilities.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(capabilities, id: \.self) { capability in
                                tagView(for: capability)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollPosition($tagsScrollPos)
#if os(macOS)
                    .onScrollGeometryChange(for: CGPoint.self) { geo in
                        geo.contentOffset
                    } action: { _, newValue in
                        currentTagsOffset = newValue
                    }
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { value in
                                if !isDraggingTags {
                                    isDraggingTags = true
                                    NSCursor.closedHand.push()
                                    dragStartOffset = currentTagsOffset
                                }
                                let deltaX = value.translation.width
                                // スクロール位置を更新
                                tagsScrollPos = ScrollPosition(point: CGPoint(x: dragStartOffset.x - deltaX, y: 0))
                            }
                            .onEnded { _ in
                                isDraggingTags = false
                                NSCursor.pop()
                            }
                    )
#endif
                    .onHover { inside in
                        #if os(macOS)
                        if inside {
                            NSCursor.openHand.push()
                        } else {
                            NSCursor.pop()
                        }
                        #endif
                    }
                    .scrollClipDisabled() // クリッピングを無効化
                }
                
                Divider()
                
                Group {
                    VStack(alignment: .leading) {
                        Text("Model Name:") // モデル名。
                        Text(model.model)
                            .font(.title3)
                            .bold()
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(model.model) // ツールチップにフルテキストを表示
                            .contextMenu {
                                Button("Copy", systemImage: copyIconName) {
#if os(macOS)
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(model.model, forType: .string)
#else
                                    UIPasteboard.general.string = model.model
#endif
                                }
                            }
                    }
                    .accessibilityElement(children: .combine)
                    VStack(alignment: .leading) {
                        Text("Size:") // サイズ。
                        Text(model.formattedSize)
                            .font(.title3)
                            .bold()
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(sizeTooltipText) // 読みやすいサイズ + フルサイズ表記をツールチップに表示
                            .contextMenu {
                                Button("Copy", systemImage: copyIconName) {
#if os(macOS)
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(fullSizeText, forType: .string)
#else
                                    UIPasteboard.general.string = fullSizeText
#endif
                                }
                            }
                    }
                    .accessibilityElement(children: .combine)
                    VStack(alignment: .leading) {
                        Text("Modified At:") // 変更日
                        Text(model.formattedModifiedAt)
                            .font(.title3)
                            .bold()
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(model.formattedModifiedAt) // ツールチップにフルテキストを表示
                            .contextMenu {
                                Button("Copy", systemImage: copyIconName) {
#if os(macOS)
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(model.formattedModifiedAt, forType: .string)
#else
                                    UIPasteboard.general.string = model.formattedModifiedAt
#endif
                                }
                            }
                    }
                    .accessibilityElement(children: .combine)
                    VStack(alignment: .leading) {
                        Text("Digest:") // ダイジェスト。
                        Text(model.digest)
                            .font(.title3)
                            .bold()
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(model.digest) // ツールチップにフルテキストを表示
                            .contextMenu {
                                Button("Copy", systemImage: copyIconName) {
#if os(macOS)
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(model.digest, forType: .string)
#else
                                    UIPasteboard.general.string = model.digest
#endif
                                }
                            }
                    }
                    .accessibilityElement(children: .combine)
                }
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
                
                Text("Details Information:") // 詳細情報（Details）。
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if let details = model.details { // ここでOptionalをアンラップします
                    VStack(alignment: .leading, spacing: 10) {
                        if let parentModel = details.parent_model, !parentModel.isEmpty {
                            VStack(alignment: .leading) {
                                Text("Parent Model:") // 親モデル。
                                Text(parentModel)
                                    .font(.title3)
                                    .bold()
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .help(parentModel) // ツールチップにフルテキストを表示
                                    .contextMenu {
                                        Button("Copy", systemImage: copyIconName) {
#if os(macOS)
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(parentModel, forType: .string)
#else
                                            UIPasteboard.general.string = parentModel
#endif
                                        }
                                    }
                            }
                        }
                        if let format = details.format {
                            VStack(alignment: .leading) {
                                Text("Format:") // フォーマット。
                                Text(format)
                                    .font(.title3)
                                    .bold()
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .help(format) // ツールチップにフルテキストを表示
                                    .contextMenu {
                                        Button("Copy", systemImage: copyIconName) {
#if os(macOS)
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(format, forType: .string)
#else
                                            UIPasteboard.general.string = format
#endif
                                        }
                                    }
                            }
                        }
                        if let family = details.family {
                            VStack(alignment: .leading) {
                                Text("Family:") // ファミリー。
                                Text(family)
                                    .font(.title3)
                                    .bold()
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .help(family) // ツールチップにフルテキストを表示
                                    .contextMenu {
                                        Button("Copy", systemImage: copyIconName) {
#if os(macOS)
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(family, forType: .string)
#else
                                            UIPasteboard.general.string = family
#endif
                                        }
                                    }
                            }
                        }
                        if let families = details.families, !families.isEmpty {
                            VStack(alignment: .leading) {
                                Text("Families:") // ファミリーズ。
                                let familiesText = families.joined(separator: ", ")
                                Text(familiesText)
                                    .font(.title3)
                                    .bold()
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .help(familiesText) // ツールチップにフルテキストを表示
                                    .contextMenu {
                                        Button("Copy", systemImage: copyIconName) {
#if os(macOS)
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(familiesText, forType: .string)
#else
                                            UIPasteboard.general.string = familiesText
#endif
                                        }
                                    }
                            }
                        }
                        if let parameterSize = details.parameter_size {
                            VStack(alignment: .leading) {
                                Text("Parameter Size:") // パラメータサイズ。
                                Text(parameterSize)
                                    .font(.title3)
                                    .bold()
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .help(parameterSize) // ツールチップにフルテキストを表示
                                    .contextMenu {
                                        Button("Copy", systemImage: copyIconName) {
#if os(macOS)
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(parameterSize, forType: .string)
#else
                                            UIPasteboard.general.string = parameterSize
#endif
                                        }
                                    }
                            }
                        }
                        if let quantizationLevel = details.quantization_level {
                            VStack(alignment: .leading) {
                                Text("Quantization Level:") // 量子化レベル。
                                Text(quantizationLevel)
                                    .font(.title3)
                                    .bold()
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .help(quantizationLevel) // ツールチップにフルテキストを表示
                                    .contextMenu {
                                        Button("Copy", systemImage: copyIconName) {
#if os(macOS)
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(quantizationLevel, forType: .string)
#else
                                            UIPasteboard.general.string = quantizationLevel
#endif
                                        }
                                    }
                            }
                        }
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No details available.") // 詳細情報はありません。
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                } else if response != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        
                        // ライセンス情報がある場合のみ表示
                        // model_infoにlicenseキーがあるか、licenseBodyがある場合
                        if response?.model_info?["general.license"] != nil || licenseBody != nil {
                            VStack(alignment: .leading) {
                                Text("License:") // ライセンス
                                if licenseBody != nil {
                                    Button(action: {
                                        showingLicenseSheet = true
                                    }) {
                                        Text(licenseName)
#if os(visionOS)
                                            .font(.body).bold()
#else
                                            .font(.title3).bold()
                                            .foregroundColor(.accentColor)
#endif
                                    }
#if os(visionOS)
                                    .buttonStyle(.bordered)
#else
                                    .buttonStyle(PlainButtonStyle())
#endif
                                } else {
                                    Text(licenseName)
                                        .font(.title3).bold()
                                }
                            }
                        }
                        
                        // パラメーターカウント
                        if let count = parameterCount {
                            VStack(alignment: .leading) {
                                Text("Parameter Count:") // パラメーターカウント
                                Text(count.formatted)
                                    .font(.title3).bold()
                                    .help(String(count.raw))
                                    .contextMenu {
                                        Button("Copy", systemImage: copyIconName) {
#if os(macOS)
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(String(count.raw), forType: .string)
#else
                                            UIPasteboard.general.string = String(count.raw)
#endif
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
                                    .help(String(length.raw))
                                    .contextMenu {
                                        Button("Copy", systemImage: copyIconName) {
#if os(macOS)
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(String(length.raw), forType: .string)
#else
                                            UIPasteboard.general.string = String(length.raw)
#endif
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
                                    .help(String(length.raw))
                                    .contextMenu {
                                        Button("Copy", systemImage: copyIconName) {
#if os(macOS)
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(String(length.raw), forType: .string)
#else
                                            UIPasteboard.general.string = String(length.raw)
#endif
                                        }
                                    }
                            }
                        }
                        
                        // 全ての詳細項目が空の場合のみ「モデル情報がありません」を表示
                        let hasLicense = response?.model_info?["general.license"] != nil || licenseBody != nil
                        let hasAnyInfo = parameterCount != nil || contextLength != nil || embeddingLength != nil || hasLicense
                        
                        if !hasAnyInfo {
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
            .id(isLoading)
#if os(visionOS)
            .transition(.opacity)
            .padding(.horizontal)
#else
            .padding()
#endif
        }
#if os(visionOS)
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 8)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 8)
        }
        .animation(.easeInOut(duration: 0.3), value: isLoading)
#endif
        .sheet(isPresented: $showingLicenseSheet) {
            if let licenseBody = licenseBody {
                LicenseTextView(licenseText: licenseBody, licenseLink: licenseLink, licenseTitle: licenseName)
            }
        }
    }
}
