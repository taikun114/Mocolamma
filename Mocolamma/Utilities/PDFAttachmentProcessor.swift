import Foundation
import PDFKit
import Vision
import UniformTypeIdentifiers
import ImageIO

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

/// PDFファイルからのテキスト抽出、OCR文字起こし、およびページ画像化を行うプロセッサ
struct PDFAttachmentProcessor: Sendable {
    static let shared = PDFAttachmentProcessor()
    
    /// PDF処理結果
    struct ProcessResult: Sendable {
        /// プロンプトに埋め込む整形済みテキスト
        let formattedPromptText: String
        /// 抽出されたテキスト（純粋なテキスト結合）
        let rawExtractedText: String
        /// 各ページのPNG画像データ（ビジョン対応モデル向け、ページ順）
        let pageImagesPNGData: [Data]
        /// 総ページ数
        let totalPages: Int
    }
    
    /// PDFデータからテキストとページ画像を抽出・処理します
    /// - Parameters:
    ///   - pdfData: PDFのバイナリデータ
    ///   - fileName: PDFのファイル名
    ///   - renderImages: ページ画像を生成するかどうか（ビジョン対応モデルの場合true）
    /// - Returns: 処理結果
    func processPDF(pdfData: Data, fileName: String, renderImages: Bool = true) async -> ProcessResult {
        guard let pdfDocument = PDFDocument(data: pdfData) else {
            // PDF読み込み失敗時のフォールバック
            let fallbackText = """
            ===
            
            Attached File: \(fileName)
            
            Page: 1 / 1 (Extracted by OCR)
            
            ``````````
            [No Text Detected by OCR]
            ``````````
            """
            return ProcessResult(
                formattedPromptText: fallbackText,
                rawExtractedText: "[No Text Detected by OCR]",
                pageImagesPNGData: [],
                totalPages: 0
            )
        }
        
        let totalPages = pdfDocument.pageCount
        guard totalPages > 0 else {
            let emptyText = """
            ===
            
            Attached File: \(fileName)
            
            Page: 1 / 1 (Extracted by OCR)
            
            ``````````
            [No Text Detected by OCR]
            ``````````
            """
            return ProcessResult(
                formattedPromptText: emptyText,
                rawExtractedText: "[No Text Detected by OCR]",
                pageImagesPNGData: [],
                totalPages: 0
            )
        }
        
        var pageBlocks: [String] = []
        var rawTexts: [String] = []
        var pageImages: [Data] = []
        
        for pageIndex in 0..<totalPages {
            let pageNumber = pageIndex + 1
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            
            // 1. PDFKitによるテキスト抽出
            let pdfKitText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            var finalText = ""
            var isOCR = false
            
            if !pdfKitText.isEmpty {
                finalText = pdfKitText
                isOCR = false
            } else {
                // 2. テキストが抽出できない場合はVisionでOCR
                isOCR = true
                if let cgImage = renderPageToCGImage(page: page, targetMaxDimension: 2048) {
                    let ocrText = performOCR(on: cgImage)
                    if !ocrText.isEmpty {
                        finalText = ocrText
                    } else {
                        finalText = "[No Text Detected by OCR]"
                    }
                } else {
                    finalText = "[No Text Detected by OCR]"
                }
            }
            
            rawTexts.append(finalText)
            
            // ページ番号ヘッダー
            let pageHeader = isOCR ? "Page: \(pageNumber) / \(totalPages) (Extracted by OCR)" : "Page: \(pageNumber) / \(totalPages)"
            
            let pageBlock = """
            \(pageHeader)
            
            ``````````
            \(finalText)
            ``````````
            """
            pageBlocks.append(pageBlock)
            
            // 3. ビジョン対応モデル向けのページ画像化（ページ順序を維持）
            if renderImages {
                if let cgImage = renderPageToCGImage(page: page, targetMaxDimension: 2048),
                   let pngData = convertCGImageToPNGData(cgImage) {
                    pageImages.append(pngData)
                }
            }
        }
        
        let formattedPromptText = """
        ===
        
        Attached File: \(fileName)
        
        \(pageBlocks.joined(separator: "\n\n---\n\n"))
        """
        
        return ProcessResult(
            formattedPromptText: formattedPromptText,
            rawExtractedText: rawTexts.joined(separator: "\n\n"),
            pageImagesPNGData: pageImages,
            totalPages: totalPages
        )
    }
    
    // MARK: - 内部ヘルパー
    
    /// Visionフレームワークを用いてオンデバイスOCRを実行します
    private func performOCR(on cgImage: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            guard let observations = request.results else {
                return ""
            }
            
            var extractedLines: [String] = []
            for observation in observations {
                if let topCandidate = observation.topCandidates(1).first {
                    let text = topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        extractedLines.append(text)
                    }
                }
            }
            
            return extractedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return ""
        }
    }
    
    /// PDFPageをCGImageとしてレンダリングします
    private func renderPageToCGImage(page: PDFPage, targetMaxDimension: CGFloat) -> CGImage? {
        let mediaBox = page.bounds(for: .mediaBox)
        guard mediaBox.width > 0, mediaBox.height > 0 else { return nil }
        
        let scale = min(targetMaxDimension / mediaBox.width, targetMaxDimension / mediaBox.height, 2.0)
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
        
        // 背景を白で塗りつぶす
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        // スケーリングと座標系の反転を適用
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        
        // PDFページの描画（PDFKitのdrawメソッドを使用）
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
        
        return context.makeImage()
    }
    
    /// CGImageをPNGデータに変換します
    private func convertCGImageToPNGData(_ cgImage: CGImage) -> Data? {
        #if os(macOS)
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
        #elseif canImport(UIKit)
        let image = UIImage(cgImage: cgImage)
        return image.pngData()
        #else
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(outputData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        
        return outputData as Data
        #endif
    }
}
