import SwiftUI
import Testing
@testable import Mocolamma

@MainActor
struct AttachmentReorderTests {
    private func attachment(_ name: String, audio: Bool) -> ChatInputAttachment {
        ChatInputAttachment(name: name, content: audio ? "" : "Notes", audioData: audio ? Data([1]) : nil)
    }

    @Test func reorderPayloadUsesAnAcceptedContentType() async throws {
        let id = UUID()
        let provider = AttachmentReorderDrag.provider(for: id)
        let type = AttachmentReorderDrag.contentType
        #expect(AttachmentReorderDrag.acceptedContentTypes.contains(type))
        #expect(provider.hasItemConformingToTypeIdentifier(type.identifier))
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
        #expect(String(data: data, encoding: .utf8) == id.uuidString)
    }

    @Test func audioReorderingPreservesDocumentOrder() {
        let first = attachment("first.m4a", audio: true)
        let second = attachment("second.mp3", audio: true)
        let doc1 = attachment("one.txt", audio: false)
        let doc2 = attachment("two.pdf", audio: false)
        var items = [first, doc1, second, doc2]
        let delegate = AttachmentDropDelegate(item: second,
            items: Binding(get: { items }, set: { items = $0 }),
            draggingItem: .constant(first), isDraggingOver: .constant(false),
            canReorder: { $0.isAudio == $1.isAudio })
        delegate.reorderItem(first)
        #expect(items.filter(\.isAudio).map(\.id) == [second.id, first.id])
        #expect(items.filter { !$0.isAudio }.map(\.id) == [doc1.id, doc2.id])
    }

    @Test func documentReorderingPreservesAudioOrder() {
        let first = attachment("first.m4a", audio: true)
        let second = attachment("second.mp3", audio: true)
        let doc1 = attachment("one.txt", audio: false)
        let doc2 = attachment("two.pdf", audio: false)
        var items = [first, doc1, second, doc2]
        let delegate = AttachmentDropDelegate(item: doc2,
            items: Binding(get: { items }, set: { items = $0 }),
            draggingItem: .constant(doc1), isDraggingOver: .constant(false),
            canReorder: { $0.isAudio == $1.isAudio })
        delegate.reorderItem(doc1)
        #expect(items.filter(\.isAudio).map(\.id) == [first.id, second.id])
        #expect(items.filter { !$0.isAudio }.map(\.id) == [doc2.id, doc1.id])
    }

    @Test func audioAndDocumentsCannotCrossGroups() {
        let audio = attachment("voice.m4a", audio: true)
        let document = attachment("notes.txt", audio: false)
        var items = [audio, document]
        for (source, target) in [(audio, document), (document, audio)] {
            let delegate = AttachmentDropDelegate(item: target,
                items: Binding(get: { items }, set: { items = $0 }),
                draggingItem: .constant(source), isDraggingOver: .constant(false),
                canReorder: { $0.isAudio == $1.isAudio })
            delegate.reorderItem(source)
            #expect(items.map(\.id) == [audio.id, document.id])
        }
    }

    @Test func dragFromAnotherGroupCannotReorderImages() {
        let first = ChatInputImage()
        let second = ChatInputImage()
        var items = [first, second]
        let delegate = ImageDropDelegate(item: second,
            items: Binding(get: { items }, set: { items = $0 }),
            draggingItem: .constant(first), isDraggingOver: .constant(false),
            isDraggingAnotherGroup: true)
        delegate.reorderItem(first)
        #expect(items.map(\.id) == [first.id, second.id])
    }
}
