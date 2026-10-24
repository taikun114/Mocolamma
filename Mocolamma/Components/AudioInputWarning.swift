import SwiftUI

/// 音声または音声と画像が非対応の場合に、対象の添付を除外して続行するか確認します。
struct AudioInputWarning: ViewModifier {
    @Binding var isPresented: Bool
    let modelName: String?
    var alsoOmitImages: Bool = false
    var hasPDFs: Bool = false
    let sendWithoutAudio: () -> Void

    private var title: Text {
        if alsoOmitImages {
            Text("This model does not support image or audio input")
        } else {
            Text("This model does not support audio input")
        }
    }

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            Button("Send") { sendWithoutAudio() }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { }
        } message: {
            if alsoOmitImages {
                if let modelName {
                    Text("The selected model \"\(modelName)\" does not support image or audio input. Image and audio attachments will be removed before sending. Are you sure you want to send it as is?")
                } else {
                    Text("The selected model does not support image or audio input. Image and audio attachments will be removed before sending. Are you sure you want to send it as is?")
                }
                if hasPDFs {
                    Text("Attached PDF files will only be sent as extracted text.")
                }
            } else if let modelName {
                Text("The selected model \"\(modelName)\" does not support audio input. Audio attachments will be removed before sending. Are you sure you want to send it as is?")
            } else {
                Text("The selected model does not support audio input. Audio attachments will be removed before sending. Are you sure you want to send it as is?")
            }
        }
    }
}
