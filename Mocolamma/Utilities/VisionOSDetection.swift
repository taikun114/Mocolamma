import Foundation
import SwiftUI

// visionOSでアプリが実行されているかどうかを検出するヘルパー
// ネイティブのvisionOSアプリとして実行されているか、またはiPadアプリとしてvisionOS上で実行されているかを判定します。

#if os(visionOS)
/// ネイティブのvisionOSアプリとして実行されているかどうか
let isNativeVisionOS: Bool = true
/// iPadアプリとしてvisionOS上で実行されているかどうか
let isiOSAppOnVision: Bool = false
#else
/// ネイティブのvisionOSアプリとして実行されているかどうか
let isNativeVisionOS: Bool = false
/// iPadアプリとしてvisionOS上で実行されているかどうか
let isiOSAppOnVision: Bool = NSClassFromString("UIWindowSceneGeometryPreferencesVision") != nil
#endif
