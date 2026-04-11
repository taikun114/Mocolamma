import Foundation
import Combine
import Observation

@Observable
class RefreshTrigger {
    @ObservationIgnored
    let publisher = PassthroughSubject<Void, Never>()
    
    func send() {
        publisher.send(())
        NotificationCenter.default.post(name: Notification.Name("InspectorRefreshRequested"), object: nil)
    }
}
