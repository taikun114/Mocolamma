import SwiftUI

/// 添付されたテキスト/Markdownファイルを表示するタイルビュー
struct FileAttachmentTileView: View {
    let fileName: String
    var size: CGFloat = 60
    var isUserBubble: Bool = false
    
    private var fileIconName: String {
        if fileName.lowercased().hasSuffix(".pdf") {
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
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(isUserBubble ? Color.white.opacity(0.2) : Color.accentColor.opacity(0.2))
                .frame(width: size, height: size)
            
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: fileIconName)
                    .font(size > 60 ? .title3 : .subheadline)
                    .foregroundStyle(isUserBubble ? .white : .primary)
                
                Spacer()
                
                Text(fileName)
                    .font(.system(size: size > 60 ? 11 : 9, weight: .medium))
                    .lineLimit(2)
                    .foregroundStyle(isUserBubble ? .white : .primary)
                    .multilineTextAlignment(.leading)
            }
            .padding(6)
            .frame(width: size, height: size, alignment: .topLeading)
        }
        .frame(width: size, height: size)
    }
}
