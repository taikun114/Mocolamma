import SwiftUI

/// 送信順に音声・画像・文書をまとめ、グループ間に区切りを表示します。
struct ChatAttachmentGroups<Audio: View, Images: View, Documents: View>: View {
    let hasAudio: Bool
    let hasImages: Bool
    let hasDocuments: Bool
    let tileSize: CGFloat
    @ViewBuilder var audio: () -> Audio
    @ViewBuilder var images: () -> Images
    @ViewBuilder var documents: () -> Documents

    var body: some View {
        HStack(spacing: 8) {
            if hasAudio {
                audio()
            }
            if hasAudio && hasImages {
                separator
            }
            if hasImages {
                images()
            }
            if hasDocuments && (hasAudio || hasImages) {
                separator
            }
            if hasDocuments {
                documents()
            }
        }
    }

    private var separator: some View {
        Divider()
            .frame(height: max(tileSize - 8, 1))
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
    }
}

#Preview("Attachment Groups") {
    ChatAttachmentGroups(hasAudio: true, hasImages: true, hasDocuments: true, tileSize: 60) {
        FileAttachmentTileView(fileName: "meeting.m4a")
        FileAttachmentTileView(fileName: "interview.mp3")
    } images: {
        Image(systemName: "photo")
            .resizable()
            .scaledToFit()
            .padding(10)
            .frame(width: 60, height: 60)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    } documents: {
        FileAttachmentTileView(fileName: "notes.txt")
        FileAttachmentTileView(fileName: "report.pdf")
    }
    .padding()
}
