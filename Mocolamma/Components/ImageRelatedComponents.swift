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
                    result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                        if let data = data {
                            Task {
                                let thumbnail = await ChatInputImage.createThumbnail(from: data)
                                await MainActor.run {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        self.parent.selectedImages.append(ChatInputImage(data: data, thumbnail: thumbnail))
                                    }
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
                    result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                        if let data = data {
                            Task {
                                let thumbnail = await ChatInputImage.createThumbnail(from: data)
                                await MainActor.run {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        self.parent.selectedImages.append(ChatInputImage(data: data, thumbnail: thumbnail))
                                    }
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
