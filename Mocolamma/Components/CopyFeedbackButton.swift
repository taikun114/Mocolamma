import SwiftUI

struct CopyFeedbackButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void
    @State private var isCopied = false
    @State private var feedbackID: UUID?

    var body: some View {
        Button {
            action()
            withAnimation(.spring()) {
                isCopied = true
            }
            feedbackID = UUID()
        } label: {
            Label {
                Text(title)
            } icon: {
                CopyFeedbackIcon(isCopied: isCopied, symbolName: systemImage)
            }
        }
        .task(id: feedbackID) {
            guard feedbackID != nil else { return }
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            withAnimation(.spring()) {
                isCopied = false
            }
        }
    }
}
