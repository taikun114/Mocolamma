import Foundation

/// PDFのページ本文と、生成に成功したページ画像の対応を保持します。
struct PDFPromptPage: Codable, Sendable {
    let number: Int
    let totalPages: Int
    let text: String
    let isOCR: Bool
    let imageIndex: Int?

    func formattedPrompt(imageNumber: Int? = nil) -> String {
        var header = "Page: \(number) / \(totalPages)"
        if let imageNumber { header += " (Image \(imageNumber))" }
        if isOCR { header += " (Extracted by OCR)" }
        return """
        \(header)

        ``````````
        \(text)
        ``````````
        """
    }
}
