import Foundation
import Testing
@testable import Mocolamma

struct ChatAttachmentSendPolicyTests {
    private var audio: ChatInputAttachment {
        ChatInputAttachment(name: "voice.m4a", content: "", audioData: Data([1]))
    }

    @Test func emptyBodyRequiresAllImageAndAudioAttachmentsToBeSupported() {
        for supportsVision in [false, true] {
            for supportsAudio in [false, true] {
                for text in ["", " \n\t"] {
                    #expect(ChatAttachmentSendPolicy.canSend(text: text, imageCount: 1, attachments: [audio], supportsVision: supportsVision, supportsAudio: supportsAudio) == (supportsVision && supportsAudio))
                }
                #expect(ChatAttachmentSendPolicy.canSend(text: "Describe", imageCount: 1, attachments: [audio], supportsVision: supportsVision, supportsAudio: supportsAudio))
            }
        }
    }

    @Test func singleMediaAndTextOnlyDocumentsUseAppropriateCapabilities() {
        for supported in [false, true] {
            #expect(ChatAttachmentSendPolicy.canSend(text: "", imageCount: 0, attachments: [audio], supportsVision: false, supportsAudio: supported) == supported)
            #expect(ChatAttachmentSendPolicy.canSend(text: "", imageCount: 1, attachments: [], supportsVision: supported, supportsAudio: false) == supported)
        }
        let pdf = ChatInputAttachment(name: "report.pdf", content: "Extracted text")
        #expect(ChatAttachmentSendPolicy.canSend(text: "", imageCount: 0, attachments: [pdf], supportsVision: false, supportsAudio: false))
        #expect(!ChatAttachmentSendPolicy.canSend(text: "", imageCount: 0, attachments: [], supportsVision: true, supportsAudio: true))
    }

    @Test func convertingAudioStillBlocksSubmission() {
        var pending = audio
        pending.isLoading = true
        #expect(!ChatAttachmentSendPolicy.canSend(text: "Describe", imageCount: 1, attachments: [pending], supportsVision: true, supportsAudio: true))
    }

    @Test(arguments: [false, true], [false, true])
    func omittedFilesCannotReappearInMessageBubbleOrRequest(skipImages: Bool, skipAudio: Bool) async throws {
        let image = ChatInputImage(data: Data([2]))
        let pdf = ChatInputAttachment(name: "report.pdf", content: "===\n\nAttached File: report.pdf\n\nPage: 1 / 1", pageImagesPNGData: [Data([3])])
        let files = [audio, pdf]
        let submission = ChatAttachmentSendPolicy.prepare(images: [image], attachments: files, skipImages: skipImages, skipAudio: skipAudio)
        let resolved = await submission.attachments.resolveProcessedAttachments(renderImages: !skipImages)
        let direct = submission.images.map { $0.data.base64EncodedString() }
        let message = ChatMessage(role: "user", content: "Describe", images: direct.isEmpty ? nil : direct, pdfImages: resolved.pdfPageImages.isEmpty ? nil : resolved.pdfPageImages, attachments: resolved.attachments)
        message.rawInputImages = submission.images
        message.rawInputAttachments = submission.attachments
        let displayedFiles = message.attachments ?? message.rawInputAttachments ?? []
        #expect(displayedFiles.contains(where: \.isAudio) == !skipAudio)
        let displaysPDF = displayedFiles.contains(where: \.isPDF)
        #expect(displaysPDF)
        #expect(message.rawInputImages?.count == (skipImages ? 0 : 1))
        #expect(message.rawInputAttachments?.contains(where: \.isAudio) == !skipAudio)
        let payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
        let expected = (skipAudio ? [] : [Data([1]).base64EncodedString()]) + (skipImages ? [] : [Data([2]).base64EncodedString(), Data([3]).base64EncodedString()])
        #expect(payload["images"] as? [String] == (expected.isEmpty ? nil : expected))
        #expect((payload["content"] as? String)?.contains("Attached Audio") == !skipAudio)
        #expect(files.count == 2)
    }
}
