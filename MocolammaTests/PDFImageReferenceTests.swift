import CoreGraphics
import Foundation
import Testing
@testable import Mocolamma

struct PDFImageReferenceTests {
    private func pdf(_ name: String, pages: [PDFPromptPage], data: [Data]) -> ChatInputAttachment {
        ChatInputAttachment(name: name, content: "===\n\nAttached File: \(name)", pageImagesPNGData: data, pdfPages: pages)
    }

    @Test(arguments: [false, true])
    func pageNumbersFollowSubmittedImagesAfterReordering(reversed: Bool) async throws {
        let first = pdf("first.pdf", pages: [
            PDFPromptPage(number: 1, totalPages: 3, text: "One", isOCR: false, imageIndex: 0),
            PDFPromptPage(number: 2, totalPages: 3, text: "Two", isOCR: true, imageIndex: nil),
            PDFPromptPage(number: 3, totalPages: 3, text: "Three", isOCR: true, imageIndex: 1)
        ], data: [Data([1]), Data([3])])
        let second = pdf("second.pdf", pages: [PDFPromptPage(number: 1, totalPages: 1, text: "Other", isOCR: false, imageIndex: 0)], data: [Data([4])])
        let audio = ChatInputAttachment(name: "voice.mp3", content: "", audioData: Data([5]))
        let attachments = [audio] + (reversed ? [second, first] : [first, second])
        let resolved = await attachments.resolveProcessedAttachments(renderImages: true)
        let message = ChatMessage(role: "user", content: "Compare", images: ["direct1", "direct2"], pdfImages: resolved.pdfPageImages, attachments: resolved.attachments)
        let payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
        let prompt = try #require(payload["content"] as? String)
        let firstIndex = reversed ? 4 : 3
        let secondIndex = reversed ? 3 : 5
        #expect(prompt.contains("excluding audio attachments"))
        #expect(prompt.contains("Images 1-2 are directly attached images."))
        #expect(prompt.contains("Attached File: first.pdf\n\nPage: 1 / 3 (Image \(firstIndex))"))
        #expect(prompt.contains("Page: 3 / 3 (Image \(firstIndex + 1)) (Extracted by OCR)"))
        #expect(!prompt.contains("Page: 2 / 3 (Image "))
        #expect(prompt.contains("Attached File: second.pdf\n\nPage: 1 / 1 (Image \(secondIndex))"))
        #expect(payload["images"] as? [String] == [Data([5]).base64EncodedString(), "direct1", "direct2"] + resolved.pdfPageImages)
        #expect(first.content == "===\n\nAttached File: first.pdf")
    }

    @Test func textOnlyPDFHasNoImageReferences() async throws {
        let attachment = pdf("report.pdf", pages: [PDFPromptPage(number: 1, totalPages: 1, text: "Notes", isOCR: false, imageIndex: 0)], data: [Data([1])])
        let resolved = await [attachment].resolveProcessedAttachments(renderImages: false)
        let message = ChatMessage(role: "user", content: "Summarize", pdfImages: resolved.pdfPageImages, attachments: resolved.attachments)
        #expect(!message.promptForAPI.contains("(Image "))
        #expect(!message.promptForAPI.contains("Image numbers"))
        #expect(message.promptForAPI.contains("Page: 1 / 1"))
        #expect(message.promptForAPI.contains("Notes"))
    }

    @Test func legacyPDFImagesStillAdvanceSubsequentImageNumbers() {
        let legacy = ChatInputAttachment(name: "legacy.pdf", content: "===\n\nAttached File: legacy.pdf", pageImagesPNGData: [Data([1]), Data([2])])
        let current = pdf("current.pdf", pages: [PDFPromptPage(number: 1, totalPages: 1, text: "New", isOCR: false, imageIndex: 0)], data: [Data([3])])
        let message = ChatMessage(role: "user", content: "Compare", images: ["direct"], pdfImages: ["old1", "old2", "new"], attachments: [legacy, current])
        #expect(message.promptForAPI.contains("Attached File: current.pdf\n\nPage: 1 / 1 (Image 4)"))
    }

    @Test func realPDFRenderingPreservesPageImageMapping() async throws {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        var box = CGRect(x: 0, y: 0, width: 120, height: 120)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        for _ in 0..<2 {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 0.5, alpha: 1))
            context.fill(CGRect(x: 20, y: 20, width: 40, height: 40))
            context.endPDFPage()
        }
        context.closePDF()
        let attachment = try #require(await ChatInputAttachment.createPDF(from: data as Data, fileName: "rendered.pdf"))
        #expect(attachment.pdfPages.map(\.number) == [1, 2])
        #expect(attachment.pdfPages.compactMap(\.imageIndex) == [0, 1])
        #expect(attachment.pageImagesPNGData.count == 2)
        let resolved = await [attachment].resolveProcessedAttachments(renderImages: true)
        let message = ChatMessage(role: "user", content: "Describe", pdfImages: resolved.pdfPageImages, attachments: resolved.attachments)
        #expect(message.promptForAPI.contains("Page: 1 / 2 (Image 1) (Extracted by OCR)"))
        #expect(message.promptForAPI.contains("Page: 2 / 2 (Image 2) (Extracted by OCR)"))
        let restored = try JSONDecoder().decode(ChatInputAttachment.self, from: JSONEncoder().encode(attachment))
        #expect(restored.pdfPages.compactMap(\.imageIndex) == [0, 1])
    }
}
