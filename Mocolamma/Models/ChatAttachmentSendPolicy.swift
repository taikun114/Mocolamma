import Foundation

/// 本文とモデルの対応状況から送信可否を判断し、送信しない添付を除外します。
enum ChatAttachmentSendPolicy {
    static func canSend(text: String, imageCount: Int, attachments: [ChatInputAttachment], supportsVision: Bool, supportsAudio: Bool) -> Bool {
        guard !attachments.contains(where: { $0.isAudio && $0.isLoading }) else { return false }
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasText {
            if imageCount > 0 && !supportsVision { return false }
            if attachments.contains(where: \.isAudio) && !supportsAudio { return false }
        }
        return hasText || (imageCount > 0 && supportsVision) || attachments.contains { !$0.isAudio || supportsAudio }
    }

    static func prepare(images: [ChatInputImage], attachments: [ChatInputAttachment], skipImages: Bool, skipAudio: Bool) -> (images: [ChatInputImage], attachments: [ChatInputAttachment]) {
        (skipImages ? [] : images, attachments.filter { !skipAudio || !$0.isAudio })
    }
}
