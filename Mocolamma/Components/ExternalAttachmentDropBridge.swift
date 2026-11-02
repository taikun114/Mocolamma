#if os(iOS)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// SwiftUIのフォーム内でも、外部アプリからのドロップを画面単位で受け取ります。
struct ExternalAttachmentDropBridge: UIViewControllerRepresentable {
    let context: AttachmentDropContext
    let executor: CommandExecutor
    let isEnabled: Bool
    var capturesDrop = false

    func makeUIViewController(context: Context) -> Controller {
        Controller(configuration: self)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.configuration = self
        controller.view.isUserInteractionEnabled = capturesDrop
    }

    final class Controller: UIViewController, UIDropInteractionDelegate {
        var configuration: ExternalAttachmentDropBridge
        private weak var targetView: UIView?
        private var interaction: UIDropInteraction?

        init(configuration: ExternalAttachmentDropBridge) {
            self.configuration = configuration
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = configuration.capturesDrop
            view.backgroundColor = .clear
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if let interaction { targetView?.removeInteraction(interaction) }
            interaction = nil
            targetView = nil
            guard let parent else { return }
            let interaction = UIDropInteraction(delegate: self)
            let target = configuration.capturesDrop ? view! : parent.view!
            target.addInteraction(interaction)
            self.interaction = interaction
            targetView = target
#if DEBUG
            print("Attachment drop: UIKit screen receiver installed")
#endif
        }

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession) -> Bool {
            let internalDrag = session.hasItemsConforming(toTypeIdentifiers: [AttachmentReorderDrag.contentType.identifier])
            let supported = session.hasItemsConforming(toTypeIdentifiers: [UTType.fileURL.identifier, UTType.image.identifier])
#if DEBUG
            print("Attachment drop: UIKit validation, enabled=\(configuration.isEnabled), supported=\(supported), internal=\(internalDrag)")
#endif
            let accepted = configuration.isEnabled && supported && !internalDrag
            if accepted && !configuration.capturesDrop {
                let configuration = configuration
                Task { @MainActor in
                    configuration.context.isExternalDragActive = true
                    configuration.executor.startDragging()
                }
            }
            return accepted
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: any UIDropSession) {
#if DEBUG
            print("Attachment drop: UIKit entered, foreground=\(configuration.capturesDrop)")
#endif
            configuration.context.isExternalDragActive = true
            configuration.executor.startDragging()
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession) -> UIDropProposal {
            configuration.executor.notifyDragActivity()
            return UIDropProposal(operation: configuration.isEnabled ? .copy : .forbidden)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: any UIDropSession) {
            configuration.executor.stopDragging()
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: any UIDropSession) {
            configuration.context.isExternalDragActive = false
            configuration.executor.stopDragging(immediate: true)
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: any UIDropSession) {
            guard configuration.isEnabled else { return }
            let configuration = configuration
            configuration.context.isExternalDragActive = false
            configuration.executor.stopDragging(immediate: true)
            let urls = session.items.map(\.itemProvider).filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
            let images = session.items.map(\.itemProvider).filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
#if DEBUG
            print("Attachment drop: UIKit receiving, urls=\(urls.count), images=\(images.count)")
#endif
            Task { @MainActor in
                if !urls.isEmpty {
                    let loaded = await DropItemLoader.loadURLs(from: urls)
                    if !loaded.isEmpty { configuration.context.request = .init(urls: loaded) }
                } else if !images.isEmpty {
                    let loaded = await DropItemLoader.loadImageData(from: images)
                    if !loaded.isEmpty { configuration.context.request = .init(imageData: loaded) }
                }
            }
        }
    }
}
#endif
