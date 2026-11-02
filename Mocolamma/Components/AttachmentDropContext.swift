import SwiftUI

/// 画面のドロップ窓口から添付一覧へ、追加と並べ替えを引き渡します。
@Observable @MainActor
final class AttachmentDropContext {
    struct Request: Identifiable {
        let id = UUID()
        var urls: [URL] = []
        var imageData: [Data] = []
        var sourceID: UUID?
        var location: CGPoint = .zero
    }

    let scope = UUID()
    var request: Request?
    var isExternalDragActive = false
    var tileFrames: [UUID: CGRect] = [:]
}

struct AttachmentScreenDropDelegate: DropDelegate {
    let context: AttachmentDropContext
    let origin: CGPoint
    let isEnabled: Bool
    let executor: CommandExecutor

    private var external: AreaImageDropDelegate {
        AreaImageDropDelegate(items: .constant([]), isDraggingOver: .constant(false), executor: executor,
                              isEnabled: isEnabled,
                              onURLsDropped: { context.request = .init(urls: $0) },
                              onDataDropped: { context.request = .init(imageData: $0) })
    }

    func validateDrop(info: DropInfo) -> Bool {
#if DEBUG
        print("Attachment drop: screen validation, enabled=\(isEnabled), image=\(info.hasItemsConforming(to: [.image])), file=\(info.hasItemsConforming(to: [.fileURL])), internal=\(AttachmentReorderDrag.isInternal(info))")
#endif
        return isEnabled
    }

    func dropEntered(info: DropInfo) {
#if DEBUG
        print("Attachment drop: screen entered, enabled=\(isEnabled)")
#endif
        if !AttachmentReorderDrag.isInternal(info) { external.dropEntered(info: info) }
    }

    func dropExited(info: DropInfo) {
        if !AttachmentReorderDrag.isInternal(info) { external.dropExited(info: info) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isEnabled else { return DropProposal(operation: .forbidden) }
        if AttachmentReorderDrag.isInternal(info) { return DropProposal(operation: .move) }
        return external.dropUpdated(info: info)
    }

    func performDrop(info: DropInfo) -> Bool {
#if DEBUG
        print("Attachment drop: screen perform, enabled=\(isEnabled)")
#endif
        guard isEnabled else { return false }
        guard AttachmentReorderDrag.isInternal(info) else { return external.performDrop(info: info) }
        guard let provider = info.itemProviders(for: [AttachmentReorderDrag.contentType]).first else { return false }
        let location = CGPoint(x: origin.x + info.location.x, y: origin.y + info.location.y)
#if DEBUG
        print("Attachment drop: screen received reorder")
#endif
        provider.loadDataRepresentation(forTypeIdentifier: AttachmentReorderDrag.contentType.identifier) { data, error in
            guard let data, let text = String(data: data, encoding: .utf8) else {
#if DEBUG
                print("Attachment drop: screen payload failed: \(String(describing: error))")
#endif
                return
            }
            let parts = text.split(separator: ":")
            guard parts.count == 2, let scope = UUID(uuidString: String(parts[0])),
                  let sourceID = UUID(uuidString: String(parts[1])) else { return }
            Task { @MainActor in
                guard scope == context.scope else { return }
                context.request = .init(sourceID: sourceID, location: location)
            }
        }
        return true
    }
}
