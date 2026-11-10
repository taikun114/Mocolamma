import SwiftUI

struct SpeechInspectorView: View {
    @Environment(SpeechSession.self) private var speech

    var body: some View {
        @Bindable var speech = speech
        Form {
            Section("Speech Generation Settings") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Voice", selection: $speech.selectedVoice) {
                        Text("Default").tag("default")
                        ForEach(speech.voices.filter { $0 != "default" }, id: \.self) { voice in
                            Text(verbatim: voice).tag(voice)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(speech.selectedModelID == nil)
                    .help("Select the voice used for speech generation.")
                    Text("Specifies the voice used for speech generation.", comment: "読み上げ生成に使用する声の種類を指定します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 200)
    }
}
