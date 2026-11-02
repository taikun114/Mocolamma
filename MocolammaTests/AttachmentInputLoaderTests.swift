import Foundation
import Testing
@testable import Mocolamma

struct AttachmentInputLoaderTests {
    @Test func recognizesImageDataWithoutUsingFileExtension() async throws {
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
        #expect(await AttachmentInputLoader.isImage(png))
        #expect(await AttachmentInputLoader.isImage(Data("Plain text".utf8)) == false)
        #expect(await AttachmentInputLoader.isImage(Data()) == false)
    }

    @Test func readsFileWithoutAcceptingItsExtensionAsImageEvidence() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let text = Data("Text with an image extension".utf8)
        try text.write(to: url)
        let loaded = try #require(await AttachmentInputLoader.read(from: url))
        #expect(loaded == text)
        #expect(await AttachmentInputLoader.isImage(loaded) == false)
    }
}
