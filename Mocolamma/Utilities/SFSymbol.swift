import Foundation

/// アプリ全体で使用されるSFSymbolのアイコン名を管理する構造体です。
/// OSバージョンによって最適なアイコンを使い分けます。
struct SFSymbol {
    /// コピー（文書）用アイコン
    static var copy: String {
        if #available(macOS 15.0, iOS 18.0, *) {
            return "document.on.document"
        } else {
            return "doc.on.doc"
        }
    }

    /// やり直し（回転矢印）用アイコン
    static var retry: String {
        if #available(macOS 15.0, iOS 18.0, *) {
            return "arrow.trianglehead.clockwise.rotate.90"
        } else {
            return "arrow.circlepath"
        }
    }
}
