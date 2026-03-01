import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - ImageDropDelegate

struct ImageDropDelegate: DropDelegate {
    let item: ChatInputImage
    @Binding var items: [ChatInputImage]
    @Binding var draggingItem: ChatInputImage?
    @Binding var isDraggingOver: Bool

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        self.draggingItem = nil
        self.isDraggingOver = false
        return true
    }

    func dropEntered(info: DropInfo) {
        self.isDraggingOver = true
        guard let draggingItem = draggingItem,
              draggingItem != item,
              let from = items.firstIndex(where: { $0.id == draggingItem.id }),
              let to = items.firstIndex(where: { $0.id == item.id }) else { return }

        if items[to].id != draggingItem.id {
            withAnimation {
                items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }
    
    func dropExited(info: DropInfo) {
        self.isDraggingOver = false
    }
}
struct AreaImageDropDelegate: DropDelegate {
    @Binding var items: [ChatInputImage]
    @Binding var isDraggingOver: Bool
    var executor: CommandExecutor?
    var isEnabled: Bool = true
    var onURLsDropped: (([URL]) -> Void)?
    var onDataDropped: (([Data]) -> Void)?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isEnabled else { return nil }
        executor?.notifyDragActivity()
        return DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard isEnabled else { return false }
        isDraggingOver = false
        executor?.stopDragging(immediate: true)

        // ファイルURLの処理 (macOSのファイル、iOSのファイルアプリ) - こちらを優先
        let urlProviders = info.itemProviders(for: [.fileURL])
        if !urlProviders.isEmpty {
            for provider in urlProviders {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            onURLsDropped?([url])
                        }
                    }
                }
            }
            return true // URLとして処理した場合は終了
        }

        // 画像データの処理 (iOSのPhotosアプリ、ブラウザなど、URLが取得できない場合)
        let imageProviders = info.itemProviders(for: [.image])
        if !imageProviders.isEmpty {
            for provider in imageProviders {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data = data {
                        DispatchQueue.main.async {
                            onDataDropped?([data])
                        }
                    }
                }
            }
            return true
        }

        return false
    }

    func dropEntered(info: DropInfo) {
        guard isEnabled else { return }
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

// MARK: - PhotoLibraryPicker

#if os(iOS)
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
