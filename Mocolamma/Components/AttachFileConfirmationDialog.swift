import SwiftUI

/// ファイルおよび画像の添付選択アクションシートを表示するViewModifier
struct AttachFileConfirmationDialogModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var showingFilePicker: Bool
    @Binding var showingPhotoPicker: Bool
    let supportsCompletion: Bool
    let supportsVision: Bool
    
    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                Text("Attach File"),
                isPresented: $isPresented,
                titleVisibility: .visible
            ) {
                if supportsCompletion {
                    Button(String(localized: "Select File...")) {
                        showingFilePicker = true
                    }
                }
                if supportsVision {
                    Button(String(localized: "Photo Library...")) {
                        showingPhotoPicker = true
                    }
                }
                Button(String(localized: "Cancel"), role: .cancel) { }
            } message: {
                Text("Select the location of the file you want to attach.")
            }
    }
}

extension View {
    /// ファイルおよび画像添付用のアクションシートを付与します
    func attachFileConfirmationDialog(
        isPresented: Binding<Bool>,
        showingFilePicker: Binding<Bool>,
        showingPhotoPicker: Binding<Bool>,
        supportsCompletion: Bool,
        supportsVision: Bool
    ) -> some View {
        modifier(AttachFileConfirmationDialogModifier(
            isPresented: isPresented,
            showingFilePicker: showingFilePicker,
            showingPhotoPicker: showingPhotoPicker,
            supportsCompletion: supportsCompletion,
            supportsVision: supportsVision
        ))
    }
}
