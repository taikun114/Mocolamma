import SwiftUI

struct LicenseTextView: View {
    let licenseText: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack {
            Text("License")
                .font(.title2)
                .bold()
                .padding(.bottom, 10)

            ScrollView {
                Text(licenseText)
                    .font(.body)
                    .monospaced()
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

            Button("Close") {
                dismiss()
            }
            .padding(.top, 10)
        }
        .padding()
        .frame(width: 700, height: 500) // シートの固定サイズを設定
    }
}