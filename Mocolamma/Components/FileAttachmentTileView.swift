import SwiftUI
import PDFKit
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// PDFの1ページ目をサムネイル画像として生成・キャッシュするローダー
final class PDFThumbnailLoader: Sendable {
    private static let cache = NSCache<NSString, PlatformImage>()
    
    /// キャッシュから同期的にサムネイルを取得します
    static func cachedThumbnail(for base64String: String) -> PlatformImage? {
        let key = cacheKey(for: base64String)
        return cache.object(forKey: key)
    }
    
    /// サムネイルをキャッシュに登録します
    static func setThumbnail(_ thumbnail: PlatformImage, for base64String: String) {
        let key = cacheKey(for: base64String)
        cache.setObject(thumbnail, forKey: key)
    }
    
    /// Base64文字列からPDFの1ページ目サムネイルを非同期生成します
    static func loadThumbnail(from base64String: String, maxPixelSize: CGFloat = 240) async -> PlatformImage? {
        if let cached = cachedThumbnail(for: base64String) {
            return cached
        }
        
        return await Task.detached(priority: .userInitiated) {
            guard let data = Data(base64Encoded: base64String) else { return nil }
            
            // 1. PNG画像データ（thumbnailBase64）の場合は直接サムネイル生成
            let imgOptions: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            if let imgSource = CGImageSourceCreateWithData(data as CFData, nil),
               let cgImage = CGImageSourceCreateThumbnailAtIndex(imgSource, 0, imgOptions as CFDictionary) {
                let thumbnail: PlatformImage
                #if os(macOS)
                thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
                #else
                thumbnail = UIImage(cgImage: cgImage)
                #endif
                setThumbnail(thumbnail, for: base64String)
                return thumbnail
            }
            
            // 2. PDFドキュメントとして1ページ目をレンダリング
            guard let document = PDFDocument(data: data),
                  document.pageCount > 0,
                  let page = document.page(at: 0) else {
                return nil
            }
            
            let mediaBox = page.bounds(for: .mediaBox)
            guard mediaBox.width > 0, mediaBox.height > 0 else { return nil }
            
            let scale = min(maxPixelSize / mediaBox.width, maxPixelSize / mediaBox.height, 2.0)
            let width = Int(mediaBox.width * scale)
            let height = Int(mediaBox.height * scale)
            guard width > 0, height > 0 else { return nil }
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else {
                return nil
            }
            
            // 白背景で塗りつぶし
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            
            // スケーリング描画
            context.saveGState()
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
            
            guard let cgImage = context.makeImage() else { return nil }
            
            let thumbnail: PlatformImage
            #if os(macOS)
            thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
            #else
            thumbnail = UIImage(cgImage: cgImage)
            #endif
            
            setThumbnail(thumbnail, for: base64String)
            return thumbnail
        }.value
    }
    
    private static func cacheKey(for base64String: String) -> NSString {
        let count = base64String.utf8.count
        let prefix = base64String.prefix(32)
        let suffix = base64String.suffix(32)
        return "pdf_\(count)_\(prefix)_\(suffix)" as NSString
    }
}

/// 添付されたテキスト/Markdown/PDFファイルを表示するタイルビュー
struct FileAttachmentTileView: View {
    let fileName: String
    var content: String? = nil
    var thumbnail: PlatformImage? = nil
    var size: CGFloat = 60
    var isUserBubble: Bool = false
    var isLoading: Bool = false
    
    @State private var loadedThumbnail: PlatformImage? = nil
    
    private var isPDF: Bool {
        fileName.lowercased().hasSuffix(".pdf")
    }
    
    private var effectiveThumbnail: PlatformImage? {
        thumbnail ?? loadedThumbnail
    }
    
    private var fileIconName: String {
        if isPDF {
            if #available(iOS 18.0, macOS 15.0, visionOS 2.0, *) {
                return "richtext.page"
            } else {
                return "doc.richtext"
            }
        } else {
            if #available(iOS 18.0, macOS 15.0, visionOS 2.0, *) {
                return "text.document"
            } else {
                return "doc.text"
            }
        }
    }
    
    init(
        fileName: String,
        content: String? = nil,
        thumbnail: PlatformImage? = nil,
        size: CGFloat = 60,
        isUserBubble: Bool = false,
        isLoading: Bool = false
    ) {
        self.fileName = fileName
        self.content = content
        self.thumbnail = thumbnail
        self.size = size
        self.isUserBubble = isUserBubble
        self.isLoading = isLoading
        if thumbnail == nil, let content = content, !content.isEmpty, fileName.lowercased().hasSuffix(".pdf") {
            self._loadedThumbnail = State(initialValue: PDFThumbnailLoader.cachedThumbnail(for: content))
        }
    }
    
    init(attachment: ChatInputAttachment, size: CGFloat = 60, isUserBubble: Bool = false, isProcessing: Bool = false) {
        let key = attachment.thumbnailBase64 ?? (attachment.content.isEmpty ? nil : attachment.content)
        self.init(
            fileName: attachment.name,
            content: key,
            thumbnail: attachment.thumbnail,
            size: size,
            isUserBubble: isUserBubble,
            isLoading: attachment.isLoading || isProcessing
        )
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            if isLoading {
                // 処理中のスピナー表示（サムネイルがあればサムネイル背景、なければ半透明図形）
                if let thumb = effectiveThumbnail {
                    #if os(macOS)
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipped()
                        .overlay(Color.black.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    #else
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipped()
                        .overlay(Color.black.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    #endif
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isUserBubble ? Color.white.opacity(0.2) : Color.gray.opacity(0.15))
                        .frame(width: size, height: size)
                }
                
                ProgressView()
                    .controlSize(.small)
                    .frame(width: size, height: size, alignment: .center)
            } else {
                // 背景レイヤー
                if let thumb = effectiveThumbnail {
                    #if os(macOS)
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipped()
                        .overlay(
                            // 明るさを下げてアイコンとテキストが見えるように暗いオーバーレイを重ねる
                            Color.black.opacity(0.45)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    #else
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipped()
                        .overlay(
                            Color.black.opacity(0.45)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    #endif
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isUserBubble ? Color.white.opacity(0.2) : Color.accentColor.opacity(0.2))
                        .frame(width: size, height: size)
                }
                
                // アイコン＆ファイル名レイヤー
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: fileIconName)
                        .font(size > 60 ? .title3 : .subheadline)
                        .foregroundStyle(effectiveThumbnail != nil || isUserBubble ? .white : .primary)
                        .shadow(color: effectiveThumbnail != nil ? .black.opacity(0.6) : .clear, radius: 1, x: 0, y: 1)
                    
                    Spacer()
                    
                    Text(fileName)
                        .font(.system(size: size > 60 ? 11 : 9, weight: .medium))
                        .lineLimit(2)
                        .foregroundStyle(effectiveThumbnail != nil || isUserBubble ? .white : .primary)
                        .multilineTextAlignment(.leading)
                        .shadow(color: effectiveThumbnail != nil ? .black.opacity(0.6) : .clear, radius: 1, x: 0, y: 1)
                }
                .padding(6)
                .frame(width: size, height: size, alignment: .topLeading)
            }
        }
        .frame(width: size, height: size)
        .task(id: content) {
            if isPDF, effectiveThumbnail == nil, let content = content, !content.isEmpty {
                self.loadedThumbnail = await PDFThumbnailLoader.loadThumbnail(from: content, maxPixelSize: size * 2.5)
            }
        }
    }
}
