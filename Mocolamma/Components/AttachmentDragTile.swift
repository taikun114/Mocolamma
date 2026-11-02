#if os(iOS) || os(visionOS)
import SwiftUI
import UIKit

/// フォーム行から独立したビューで、添付ファイルのドラッグを扱います。
struct AttachmentDragTile<Content: View>: UIViewControllerRepresentable {
    let id: UUID
    let scope: UUID
    let canMove: (UUID) -> Bool
    let move: (UUID) -> Void
    var onBegin: () -> Void = {}
    var onEnd: () -> Void = {}
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: hostedContent())
        controller.safeAreaRegions = []
        controller.view.backgroundColor = .clear
#if os(iOS)
        let drag = UIDragInteraction(delegate: context.coordinator)
        drag.isEnabled = true
        controller.view.addInteraction(drag)
        controller.view.addInteraction(UIDropInteraction(delegate: context.coordinator))
#endif
        return controller
    }

    func updateUIViewController(_ controller: UIHostingController<AnyView>, context: Context) {
        context.coordinator.parent = self
        controller.rootView = hostedContent()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIHostingController<AnyView>, context: Context) -> CGSize? {
        CGSize(width: 68, height: 68)
    }

    private func hostedContent() -> AnyView {
#if os(visionOS)
        AnyView(content()
            .contentShape(Rectangle())
            .onDrag {
                let provider = NSItemProvider()
                let data = Data("\(scope.uuidString):\(id.uuidString)".utf8)
                provider.registerDataRepresentation(forTypeIdentifier: AttachmentReorderDrag.contentType.identifier, visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
#if DEBUG
                print("Attachment drag: hosted source began")
#endif
                return provider
            }
            .onDrop(of: [AttachmentReorderDrag.contentType], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
#if DEBUG
                print("Attachment drop: hosted target received")
#endif
                provider.loadDataRepresentation(forTypeIdentifier: AttachmentReorderDrag.contentType.identifier) { data, error in
                    guard let data, let text = String(data: data, encoding: .utf8) else {
#if DEBUG
                        print("Attachment drop: failed to load reorder payload: \(String(describing: error))")
#endif
                        return
                    }
                    let parts = text.split(separator: ":")
                    guard parts.count == 2,
                          let sourceScope = UUID(uuidString: String(parts[0])),
                          let sourceID = UUID(uuidString: String(parts[1])) else { return }
                    Task { @MainActor in
                        guard sourceScope == scope, canMove(sourceID), sourceID != id else { return }
                        move(sourceID)
                    }
                }
                return true
            })
#else
        AnyView(content())
#endif
    }

    private final class Payload {
        let id: UUID
        let scope: UUID
        init(id: UUID, scope: UUID) { self.id = id; self.scope = scope }
    }

    final class Coordinator: NSObject, UIDragInteractionDelegate, UIDropInteractionDelegate {
        var parent: AttachmentDragTile
        init(parent: AttachmentDragTile) { self.parent = parent }

        func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: any UIDragSession) -> [UIDragItem] {
#if DEBUG
            print("Attachment drag: began")
#endif
            parent.onBegin()
            let item = UIDragItem(itemProvider: AttachmentReorderDrag.provider(for: parent.id, includesText: false))
            item.localObject = Payload(id: parent.id, scope: parent.scope)
            return [item]
        }

        func dragInteraction(_ interaction: UIDragInteraction, sessionIsRestrictedToDraggingApplication session: any UIDragSession) -> Bool { true }

        func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem, session: any UIDragSession) -> UITargetedDragPreview? {
            guard let view = interaction.view else { return nil }
            let parameters = UIDragPreviewParameters()
            parameters.backgroundColor = .clear
            return UITargetedDragPreview(view: view, parameters: parameters)
        }

        private func source(in session: any UIDropSession) -> UUID? {
            guard session.localDragSession != nil,
                  let payload = session.items.first?.localObject as? Payload,
                  payload.scope == parent.scope,
                  parent.canMove(payload.id) else { return nil }
            return payload.id
        }

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession) -> Bool {
            let accepted = source(in: session) != nil
#if DEBUG
            let payload = session.items.first?.localObject as? Payload
            print("Attachment drop: canHandle=\(accepted), localSession=\(session.localDragSession != nil), payload=\(payload != nil), matchingScope=\(payload?.scope == parent.scope), allowsMove=\(session.allowsMoveOperation)")
#endif
            return accepted
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession) -> UIDropProposal {
            UIDropProposal(operation: source(in: session) == nil ? .forbidden : .move)
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: any UIDropSession) {
#if DEBUG
            print("Attachment drop: performDrop, accepted=\(source(in: session) != nil)")
#endif
            guard let id = source(in: session), id != parent.id else { return }
            parent.move(id)
        }

        func dragInteraction(_ interaction: UIDragInteraction, session: any UIDragSession, didEndWith operation: UIDropOperation) {
            parent.onEnd()
#if DEBUG
            print("Attachment drag: ended, operation=\(operation.rawValue)")
#endif
        }

        func dropInteraction(_ interaction: UIDropInteraction, previewForDropping item: UIDragItem, withDefault defaultPreview: UITargetedDragPreview) -> UITargetedDragPreview? {
            guard let view = interaction.view else { return nil }
            let parameters = UIDragPreviewParameters()
            parameters.backgroundColor = .clear
            return UITargetedDragPreview(view: view, parameters: parameters)
        }
    }
}
#endif
