import Foundation
import ImageIO
import UniformTypeIdentifiers

enum AttachmentInputLoader {
    static func read(from url: URL) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            do {
                return try Data(contentsOf: url)
            } catch {
#if DEBUG
                print("Attachment file read failed: \(error.localizedDescription)")
#endif
                return nil
            }
        }.value
    }

    static func isImage(_ data: Data) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            // 画像の展開やHDR変換をせず、形式だけを確認します。
            let options = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, options),
                  let identifier = CGImageSourceGetType(source),
                  let type = UTType(identifier as String) else { return false }
            return type.conforms(to: .image)
        }.value
    }
}
