#if os(iOS)
import SwiftUI

enum DecisionGroupedMetrics {
    static var horizontalInset: CGFloat {
        if #available(iOS 26, *) { 20 } else { 16 }
    }

    static var inputInsets: EdgeInsets {
        let vertical: CGFloat
        if #available(iOS 26, *) { vertical = 12 } else { vertical = 12 }
        return EdgeInsets(top: vertical, leading: horizontalInset, bottom: vertical, trailing: horizontalInset)
    }

    static var resultInsets: EdgeInsets {
        let vertical: CGFloat
        if #available(iOS 26, *) { vertical = 20 } else { vertical = 12 }
        return EdgeInsets(top: vertical, leading: horizontalInset, bottom: vertical, trailing: horizontalInset)
    }

    static var cornerRadius: CGFloat {
        if #available(iOS 26, *) { 26 } else { 10 }
    }

    static var headerFont: Font {
        if #available(iOS 26, *) { .headline } else { .subheadline }
    }
}

struct DecisionGroupedSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DecisionGroupedMetrics.headerFont)
                .foregroundStyle(.secondary)
                .padding(.horizontal, DecisionGroupedMetrics.horizontalInset)
                .accessibilityAddTraits(.isHeader)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: DecisionGroupedMetrics.cornerRadius, style: .continuous))
        }
    }
}
#endif
