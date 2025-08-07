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
    private init() {}
    
    private let key = "api_timeout_option"
    
    var currentOption: APITimeoutOption {
        get {
            if let raw = UserDefaults.standard.string(forKey: key), let opt = APITimeoutOption(rawValue: raw) {
                return opt
            }
            return .seconds30
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
    
    func set(option: APITimeoutOption) {
        currentOption = option
        NotificationCenter.default.post(name: .apiTimeoutChanged, object: option)
    }
}

extension Notification.Name {
    static let apiTimeoutChanged = Notification.Name("apiTimeoutChanged")
}
