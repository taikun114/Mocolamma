import SwiftUI

struct AdaptiveSegmentedPickerRow<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(title).fixedSize()
                Spacer(minLength: 12)
                content().fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).fixedSize(horizontal: false, vertical: true)
                content()
                    .buttonSizingFlexibleIfAvailable()
                    .frame(maxWidth: .infinity)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
