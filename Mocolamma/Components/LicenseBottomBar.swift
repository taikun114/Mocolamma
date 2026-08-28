import SwiftUI

#if os(macOS)
extension View {
    /// 閉じるボタンのみのライセンスボトムバー
    @ViewBuilder
    func licenseBottomBar(dismissAction: @escaping () -> Void) -> some View {
        licenseBottomBar(dismissAction: dismissAction, leading: { EmptyView() })
    }
    
    /// カスタム先頭要素を含むライセンスボトムバー
    @ViewBuilder
    func licenseBottomBar<Leading: View>(
        dismissAction: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading
    ) -> some View {
        let bar = HStack {
            leading()
            Spacer()
            Button("Close") {
                dismissAction()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)
        }
        .padding()
        
        if #available(macOS 26, *) {
            self.safeAreaBar(edge: .bottom, spacing: 0) {
                bar
            }
            .adaptiveScrollEdgeEffect()
        } else {
            self.safeAreaInset(edge: .bottom, spacing: 0) {
                bar
                    .background {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .edgesIgnoringSafeArea(.horizontal)
                    }
            }
        }
    }
}
#endif
