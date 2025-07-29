import SwiftUI

struct ChatMessagesView: View {
    @Binding var messages: [ChatMessage]
    var body: some View {
        if #available(macOS 26, *) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        MessageView(message: message)
                            .id(message.id)
                    }
                }
                .padding()
                .padding(.top, 60) // Height of the top overlay
                .padding(.bottom, 50) // Height of the bottom overlay
            }
            .scrollEdgeEffectStyle(.hard, for: .all)

        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        MessageView(message: message)
                            .id(message.id)
                    }
                }
                .padding()
                .padding(.top, 60) // Height of the top overlay
                .padding(.bottom, 50) // Height of the bottom overlay
            }
        }

    }
}
