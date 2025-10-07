import Foundation

enum APITimeoutOption: String, CaseIterable, Codable, Equatable, Identifiable {
    case seconds30
    case minutes1
    case minutes5
    case unlimited
    var id: String { rawValue }
    
    var requestTimeoutUntilFirstByte: TimeInterval {
        switch self {
        case .seconds30: return 30
        case .minutes1: return 60
        case .minutes5: return 300
        case .unlimited: return 0
        }
    }
    
    var overallResourceTimeout: TimeInterval { 0 }
}

final class APITimeoutManager {
    static let shared = APITimeoutManager()
    private let key = "api_timeout_option"
    
    @Published private(set) var currentOption: APITimeoutOption = .seconds30
    
    private init() {
        Task {
            if let raw = UserDefaults.standard.string(forKey: key),
               let savedOption = APITimeoutOption(rawValue: raw) {
                
                await MainActor.run {
                    self.set(option: savedOption)
                }
            }
        }
    }
    
    func set(option: APITimeoutOption) {
        guard option != currentOption else { return }
        currentOption = option
        UserDefaults.standard.set(option.rawValue, forKey: key)
        NotificationCenter.default.post(name: .apiTimeoutChanged, object: option)
    }
}

extension Notification.Name {
    static let apiTimeoutChanged = Notification.Name("apiTimeoutChanged")
}