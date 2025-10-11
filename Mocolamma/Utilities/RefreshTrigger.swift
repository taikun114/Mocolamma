import Foundation
import Combine

class RefreshTrigger: ObservableObject {
    let publisher = PassthroughSubject<Void, Never>()

    func send() {
        publisher.send(())
        NotificationCenter.default.post(name: Notification.Name("InspectorRefreshRequested"), object: nil)
    }
}
