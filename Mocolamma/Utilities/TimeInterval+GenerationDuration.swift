import Foundation

extension TimeInterval {
    var generationDurationDescription: String {
        guard isFinite, self >= 0, self < Double(Int.max) else { return String(localized: "Unknown") }
        if self >= 60 {
            let wholeSeconds = Int(self)
            let hours = wholeSeconds / 3600
            let minutes = (wholeSeconds % 3600) / 60
            let seconds = wholeSeconds % 60
            var parts: [String] = []
            if hours > 0 {
                parts.append(String.localizedStringWithFormat(String(localized: "%dh"), hours))
            }
            parts.append(String.localizedStringWithFormat(String(localized: "%dm"), minutes))
            parts.append(String.localizedStringWithFormat(String(localized: "%ds"), seconds))
            return parts.joined()
        }
        if self > 1 {
            let value = formatted(.number.precision(.fractionLength(3)))
            return String(localized: "\(value) s")
        }
        let value = (self * 1000).formatted(.number.precision(.fractionLength(2)))
        return String(localized: "\(value) ms")
    }
}
