import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - 並び替え用DropDelegate

/// アイテムの並び替えを行う汎用DropDelegate
struct ItemReorderDropDelegate<T: Identifiable & Equatable>: DropDelegate {
    let item: T
    @Binding var items: [T]
    @Binding var draggingItem: T?
    @Binding var isDraggingOver: Bool
    var executor: CommandExecutor? = nil
    var onURLsDropped: (([URL]) -> Void)? = nil
    var onDataDropped: (([Data]) -> Void)? = nil

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if draggingItem != nil {
            // アプリ内アイテムの並び替え時
            return DropProposal(operation: .move)
        } else {
            // 外部からのファイル/画像ドラッグ時
            let providers = info.itemProviders(for: [.image, .fileURL, .text])
            let hasValidItem = providers.contains { provider in
                provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
                provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ||
                provider.hasItemConformingToTypeIdentifier(UTType.text.identifier)
            }
            guard hasValidItem else { return nil }
            executor?.notifyDragActivity()
            return DropProposal(operation: .copy)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        if draggingItem != nil {
            self.draggingItem = nil
            self.isDraggingOver = false
            return true
        }
        
        self.isDraggingOver = false
        executor?.stopDragging(immediate: true)
        
        let urlProviders = info.itemProviders(for: [.fileURL])
        let imageProviders = info.itemProviders(for: [.image])
        
        if !urlProviders.isEmpty {
            Task { @MainActor in
                let urls = await DropItemLoader.loadURLs(from: urlProviders)
                if !urls.isEmpty {
                    onURLsDropped?(urls)
                }
            }
            return true
        }
        
        if !imageProviders.isEmpty {
            Task { @MainActor in
                let dataList = await DropItemLoader.loadImageData(from: imageProviders)
                if !dataList.isEmpty {
                    onDataDropped?(dataList)
                }
            }
            return true
        }

        return false
    }

    func dropEntered(info: DropInfo) {
        if let draggingItem = draggingItem {
            // 並び替え時
            guard draggingItem != item,
                  let from = items.firstIndex(where: { $0.id == draggingItem.id }),
                  let to = items.firstIndex(where: { $0.id == item.id }) else { return }

            if items[to].id != draggingItem.id {
                withAnimation {
                    items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
            }
        } else {
            // 外部ファイルドラッグ時
            let providers = info.itemProviders(for: [.image, .fileURL, .text])
            let hasValidItem = providers.contains { provider in
                provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
                provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ||
                provider.hasItemConformingToTypeIdentifier(UTType.text.identifier)
            }
            guard hasValidItem else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                self.isDraggingOver = true
                executor?.startDragging()
            }
            executor?.notifyDragActivity()
        }
    }
    
    func dropExited(info: DropInfo) {
        if draggingItem != nil {
            self.isDraggingOver = false
        } else {
            executor?.notifyDragActivity()
        }
    }
}

typealias ImageDropDelegate = ItemReorderDropDelegate<ChatInputImage>
typealias AttachmentDropDelegate = ItemReorderDropDelegate<ChatInputAttachment>
struct AreaImageDropDelegate: DropDelegate {
    @Binding var items: [ChatInputImage]
    @Binding var isDraggingOver: Bool
    var executor: CommandExecutor?
    var isEnabled: Bool = true
    var onURLsDropped: (([URL]) -> Void)?
    var onDataDropped: (([Data]) -> Void)?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isEnabled else { return nil }
        
        // ドラッグされているアイテムに画像、ファイルURL、テキストが含まれているか確認
        let providers = info.itemProviders(for: [.image, .fileURL, .text])
        let hasValidItem = providers.contains { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ||
            provider.hasItemConformingToTypeIdentifier(UTType.text.identifier)
        }
        
        guard hasValidItem else { return nil }
        
        executor?.notifyDragActivity()
        return DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard isEnabled else { return false }
        isDraggingOver = false
        executor?.stopDragging(immediate: true)

        let urlProviders = info.itemProviders(for: [.fileURL])
        let imageProviders = info.itemProviders(for: [.image])

        if !urlProviders.isEmpty {
            Task { @MainActor in
                let urls = await DropItemLoader.loadURLs(from: urlProviders)
                if !urls.isEmpty {
                    onURLsDropped?(urls)
                }
            }
            return true
        }

        if !imageProviders.isEmpty {
            Task { @MainActor in
                let dataList = await DropItemLoader.loadImageData(from: imageProviders)
                if !dataList.isEmpty {
                    onDataDropped?(dataList)
                }
            }
            return true
        }

        return false
    }

    func dropEntered(info: DropInfo) {
        guard isEnabled else { return }
        
        // ドラッグされているアイテムに画像、ファイルURL、テキストが含まれているか確認
        let providers = info.itemProviders(for: [.image, .fileURL, .text])
        let hasValidItem = providers.contains { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ||
            provider.hasItemConformingToTypeIdentifier(UTType.text.identifier)
        }
        
        guard hasValidItem else { return }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            isDraggingOver = true
            executor?.startDragging()
        }
    }

    func dropExited(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.2)) {
            isDraggingOver = false
        }
        executor?.notifyDragActivity()
    }
}

// MARK: - ドロップアイテム非同期ローダー

/// ドラッグ＆ドロップされたアイテム（URLや画像データ）を非同期並列でロードするヘルパー
enum DropItemLoader {
    /// NSItemProvider配列からファイルURLを並列ロードします
    static func loadURLs(from providers: [NSItemProvider]) async -> [URL] {
        await withTaskGroup(of: URL?.self) { group in
            for provider in providers {
                group.addTask {
                    await withCheckedContinuation { continuation in
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            continuation.resume(returning: url)
                        }
                    }
                }
            }
            var urls: [URL] = []
            for await url in group {
                if let url = url {
                    urls.append(url)
                }
            }
            return urls
        }
    }

    /// NSItemProvider配列から画像データを並列ロードします
    static func loadImageData(from providers: [NSItemProvider]) async -> [Data] {
        await withTaskGroup(of: Data?.self) { group in
            for provider in providers {
                group.addTask {
                    await withCheckedContinuation { continuation in
                        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                            continuation.resume(returning: data)
                        }
                    }
                }
            }
            var dataList: [Data] = []
            for await data in group {
                if let data = data {
                    dataList.append(data)
                }
            }
            return dataList
        }
    }
}

// MARK: - サムネイル画像ローダー＆キャッシュ

/// Base64文字列からサムネイル画像を非同期にロード・キャッシュするマネージャー
final class ImageThumbnailLoader: Sendable {
    private static let cache = NSCache<NSString, PlatformImage>()

    /// キャッシュから即座にサムネイルを取得します（同期）
    static func cachedThumbnail(for base64String: String) -> PlatformImage? {
        let key = cacheKey(for: base64String)
        return cache.object(forKey: key)
    }
    
    /// サムネイル画像をキャッシュに登録します
    static func setThumbnail(_ image: PlatformImage, for base64String: String) {
        let key = cacheKey(for: base64String)
        cache.setObject(image, forKey: key)
    }

    /// Base64文字列からサムネイル画像を取得します（キャッシュ優先、非同期バックグラウンド生成）
    static func loadThumbnail(from base64String: String, maxPixelSize: CGFloat = 240) async -> PlatformImage? {
        let key = cacheKey(for: base64String)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        return await Task.detached(priority: .userInitiated) {
            guard let data = Data(base64Encoded: base64String) else { return nil }

            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]

            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }

            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            let size = min(width, height)
            let x = (width - size) / 2
            let y = (height - size) / 2
            let cropRect = CGRect(x: x, y: y, width: size, height: size)

            guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
                return nil
            }

            #if os(macOS)
            let image = NSImage(cgImage: croppedCGImage, size: NSSize(width: maxPixelSize / 2, height: maxPixelSize / 2))
            #else
            let image = UIImage(cgImage: croppedCGImage)
            #endif

            cache.setObject(image, forKey: key)
            return image
        }.value
    }

    /// Base64文字列からフル解像度の画像を取得します（非同期バックグラウンドデコード）
    static func loadFullImage(from base64String: String) async -> PlatformImage? {
        return await Task.detached(priority: .userInitiated) {
            guard let data = Data(base64Encoded: base64String) else { return nil }
            return PlatformImage(data: data)
        }.value
    }

    /// キャッシュ用キー（先頭・末尾・長さを組み合わせて高速にハッシュ化）
    private static func cacheKey(for base64String: String) -> NSString {
        let count = base64String.utf8.count
        let prefix = base64String.prefix(32)
        let suffix = base64String.suffix(32)
        return "\(count)_\(prefix)_\(suffix)" as NSString
    }
}

// MARK: - メッセージ添付サムネイル画像ビュー

/// メッセージバブル内で添付画像を軽量なサムネイルとして表示するビュー
struct MessageThumbnailImageView: View {
    let base64String: String
    let size: CGFloat
    var onPreview: ((PlatformImage) -> Void)? = nil

    @State private var thumbnail: PlatformImage?

    init(base64String: String, size: CGFloat, onPreview: ((PlatformImage) -> Void)? = nil) {
        self.base64String = base64String
        self.size = size
        self.onPreview = onPreview
        self._thumbnail = State(initialValue: ImageThumbnailLoader.cachedThumbnail(for: base64String))
    }

    var body: some View {
        ZStack {
            if let image = thumbnail {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let onPreview = onPreview {
                            Task {
                                if let fullImage = await ImageThumbnailLoader.loadFullImage(from: base64String) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        onPreview(fullImage)
                                    }
                                }
                            }
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: size, height: size)
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                    }
            }
        }
        .task {
            if thumbnail == nil {
                if let cached = ImageThumbnailLoader.cachedThumbnail(for: base64String) {
                    self.thumbnail = cached
                } else {
                    self.thumbnail = await ImageThumbnailLoader.loadThumbnail(from: base64String, maxPixelSize: size * 2.5)
                }
            }
        }
    }
}

// MARK: - PhotoLibraryPicker

#if !os(macOS)
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    @Binding var selectedImages: [ChatInputImage]

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 0
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker

        init(_ parent: PhotoLibraryPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            
            for result in results {
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    let placeholderId = UUID()
                    let task = Task<ChatInputImage?, Never> {
                        await withCheckedContinuation { continuation in
                            result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                                if let data = data {
                                    Task {
                                        let image = await ChatInputImage.create(from: data, id: placeholderId)
                                        continuation.resume(returning: image)
                                    }
                                } else {
                                    continuation.resume(returning: nil)
                                }
                            }
                        }
                    }
                    
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.parent.selectedImages.append(ChatInputImage(id: placeholderId, isLoading: true, loadTask: task))
                    }
                    
                    Task {
                        if let chatInputImage = await task.value {
                            await MainActor.run {
                                if let index = self.parent.selectedImages.firstIndex(where: { $0.id == placeholderId }) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        self.parent.selectedImages[index] = chatInputImage
                                    }
                                }
                            }
                        } else {
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    self.parent.selectedImages.removeAll(where: { $0.id == placeholderId })
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
#else
struct PhotoLibraryPicker: NSViewControllerRepresentable {
    @Binding var isPresented: Bool
    @Binding var selectedImages: [ChatInputImage]

    func makeNSViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 0
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateNSViewController(_ nsViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker

        init(_ parent: PhotoLibraryPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            
            for result in results {
                if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    let placeholderId = UUID()
                    let task = Task<ChatInputImage?, Never> {
                        await withCheckedContinuation { continuation in
                            result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                                if let data = data {
                                    Task {
                                        let image = await ChatInputImage.create(from: data, id: placeholderId)
                                        continuation.resume(returning: image)
                                    }
                                } else {
                                    continuation.resume(returning: nil)
                                }
                            }
                        }
                    }
                    
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.parent.selectedImages.append(ChatInputImage(id: placeholderId, isLoading: true, loadTask: task))
                    }
                    
                    Task {
                        if let chatInputImage = await task.value {
                            await MainActor.run {
                                if let index = self.parent.selectedImages.firstIndex(where: { $0.id == placeholderId }) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        self.parent.selectedImages[index] = chatInputImage
                                    }
                                }
                            }
                        } else {
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    self.parent.selectedImages.removeAll(where: { $0.id == placeholderId })
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
#endif
