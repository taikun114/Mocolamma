import SwiftUI
import UniformTypeIdentifiers

struct SpeechSaveButton: View {
    let audio: SpeechAudioExport?
    @State private var exportItem: SpeechAudioExport?
    @State private var isExporterPresented = false
    @State private var isSaved = false
    @State private var feedbackID: UUID?
    @State private var saveError: String?

    var body: some View {
        Button {
            guard let audio else { return }
            exportItem = audio
            isExporterPresented = true
        } label: {
            ZStack {
                Image(systemName: "arrow.down.to.line").hidden()
                Image(systemName: "checkmark").hidden()
                Image(systemName: isSaved ? "checkmark" : "arrow.down.to.line")
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Rectangle())
            .padding(5)
        }
        .accessibilityLabel("Save as File...")
        .help("Save as File...")
#if os(macOS)
        .font(.caption2)
#else
        .font(.body)
#endif
#if os(visionOS)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
#else
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
#endif
        .disabled(audio == nil)
        .fileExporter(isPresented: $isExporterPresented, item: exportItem, contentTypes: [.wav], defaultFilename: "Speech.wav") { result in
            exportItem = nil
            switch result {
            case .success(let url):
                print("Speech audio saved to: \(url.path)")
                withAnimation(.spring()) { isSaved = true }
                feedbackID = UUID()
            case .failure(let error):
                print("Speech audio save failed: \(error.localizedDescription)")
                saveError = error.localizedDescription
            }
        } onCancellation: {
            exportItem = nil
        }
        .alert("Error Occurred", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: {
            Text(verbatim: saveError ?? "")
        }
        .task(id: feedbackID) {
            guard feedbackID != nil else { return }
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            withAnimation(.spring()) { isSaved = false }
        }
    }
}
