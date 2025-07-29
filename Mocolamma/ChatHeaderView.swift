import SwiftUI

struct ChatHeaderView: View {
    @Binding var selectedModel: OllamaModel?
    @Binding var showingModelSelectionSheet: Bool
    let models: [OllamaModel]

    var body: some View {
        ZStack {
            // macOS 26以降であればglassEffect、それ以外はVisualEffectView
            if #available(macOS 26, *) {
                Color.clear
                    .glassEffect()
                    .edgesIgnoringSafeArea(.horizontal)
            } else {
                VisualEffectView(material: .headerView, blendingMode: .withinWindow)
                    .edgesIgnoringSafeArea(.horizontal)
            }
            HStack {
                Text("Selected Model:")
                    .font(.headline)
                Button(action: {
                    showingModelSelectionSheet = true
                }) {
                    Text(selectedModel?.name ?? "Select Model")
                        .font(.headline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $showingModelSelectionSheet, attachmentAnchor: .point(.bottom), arrowEdge: .bottom) {
                    ModelSelectionSheet(selectedModel: $selectedModel, models: models)
                }
                Spacer()
            }
            .padding()
        }
        .frame(height: 60) // Fixed height for the top overlay
    }
}
