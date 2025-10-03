import Foundation
import SwiftUI

// Helper to detect if the app is running on visionOS
let isiOSAppOnVision: Bool = NSClassFromString("UIWindowSceneGeometryPreferencesVision") != nil