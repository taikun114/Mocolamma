#if canImport(UIKit)
import SwiftUI
import UIKit

struct CopyValueEditMenu: UIViewRepresentable {
    let value: String

    func makeCoordinator() -> Coordinator {
        Coordinator(value: value)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        let interaction = UIEditMenuInteraction(delegate: context.coordinator)
        view.addInteraction(interaction)
        context.coordinator.interaction = interaction
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.showMenu(_:)))
        longPress.cancelsTouchesInView = false
        view.addGestureRecognizer(longPress)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.value = value
    }

    final class Coordinator: NSObject, UIEditMenuInteractionDelegate {
        var value: String
        var interaction: UIEditMenuInteraction?

        init(value: String) {
            self.value = value
        }

        @objc func showMenu(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let view = recognizer.view else { return }
            let configuration = UIEditMenuConfiguration(identifier: nil, sourcePoint: recognizer.location(in: view))
            interaction?.presentEditMenu(with: configuration)
        }

        func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
                                 suggestedActions: [UIMenuElement]) -> UIMenu? {
            let value = value
            return UIMenu(children: [UIAction(title: String(localized: "Copy"), image: UIImage(systemName: SFSymbol.copy)) { _ in
                UIPasteboard.general.string = value
            }])
        }
    }
}
#endif
