import SwiftUI

struct DecisionColumns<Input: View, Results: View>: View {
    @Environment(\.layoutDirection) private var layoutDirection
    @ViewBuilder var input: () -> Input
    @ViewBuilder var results: () -> Results

    var body: some View {
#if os(iOS)
        if #available(iOS 27.1, *) {
            GeometryReader { geometry in
                let fold = geometry.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)
                    .first { $0.isActive && $0.frame.height > $0.frame.width }
                let splitX = min(geometry.size.width, max(0, fold?.frame.midX ?? geometry.size.width / 2))
                let inputWidth = layoutDirection == .rightToLeft ? geometry.size.width - splitX : splitX
                HStack(alignment: .top, spacing: 0) {
                    input().frame(width: inputWidth)
                    results().frame(width: geometry.size.width - inputWidth)
                }
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 0) { Divider() }
                        .frame(width: 1, height: geometry.size.height)
                        .position(x: splitX, y: geometry.size.height / 2)
                        .allowsHitTesting(false)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
        } else {
            HStack(spacing: 0) {
                input()
                Divider().padding(.horizontal, 8)
                results()
            }
        }
#else
        HStack(alignment: .top, spacing: 0) {
            input()
            Divider()
            results()
        }
#endif
    }
}
