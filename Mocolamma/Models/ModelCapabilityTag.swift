import Foundation

struct ModelCapabilityTag {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    private var normalizedValue: String { rawValue.lowercased() }

    var sortOrder: Int {
        switch normalizedValue {
        case "completion": return 1
        case "thinking": return 2
        case "tools": return 3
        case "vision": return 4
        case "audio": return 5
        case "embedding": return 6
        case "image": return 7
        case "speech": return 8
        case "decision": return 9
        default: return 100
        }
    }

    var displayName: String {
        switch normalizedValue {
        case "completion": return String(localized: "Text Generation")
        case "thinking": return String(localized: "Thinking")
        case "tools": return String(localized: "Tool Calling")
        case "vision": return String(localized: "Image Input")
        case "audio": return String(localized: "Audio Input")
        case "embedding": return String(localized: "Embedding")
        case "image": return String(localized: "Image Generation")
        case "speech": return String(localized: "Speech Generation")
        case "decision": return String(localized: "Decision")
        default: return rawValue.capitalized
        }
    }

    var iconName: String {
        switch normalizedValue {
        case "completion": return "character.cursor.ibeam"
        case "thinking": return "brain.filled.head.profile"
        case "tools": return "wrench.and.screwdriver"
        case "vision": return "eye"
        case "audio": return "music.note"
        case "embedding": return "square.stack.3d.up"
        case "image": return "photo"
        case "speech": return "person.wave.2"
        case "decision": return "checklist"
        default: return "tag"
        }
    }
}
