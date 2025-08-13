import SwiftUI

// MARK: - Model Inspector Detail View Helper
struct ModelInspectorDetailView: View {
    let model: OllamaModel
    let modelInfo: [String: JSONValue]?
    let isLoading: Bool
    let fetchedCapabilities: [String]?
    let licenseBody: String?
    let licenseLink: String?

    var body: some View {
        ModelInspectorView(
            model: model,
            modelInfo: modelInfo,
            isLoading: isLoading,
            fetchedCapabilities: fetchedCapabilities,
            licenseBody: licenseBody,
            licenseLink: licenseLink
        )
    }
}
