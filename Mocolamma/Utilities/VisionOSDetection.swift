import Foundation
import SwiftUI

// visionOSでアプリが実行されているかどうかを検出するヘルパー
let isiOSAppOnVision: Bool = NSClassFromString("UIWindowSceneGeometryPreferencesVision") != nil