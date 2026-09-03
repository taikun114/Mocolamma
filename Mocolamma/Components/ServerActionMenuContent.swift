import SwiftUI

/// サーバーに対する各種操作（選択、編集、削除など）を提供する共通メニューコンテンツです。
/// コンテキストメニューおよびツールバーのアクションメニューで共通して使用されます。
struct ServerActionMenuContent: View {
    let server: ServerInfo
    var serverManager: ServerManager
    var onEdit: (ServerInfo) -> Void
    var onDelete: (ServerInfo) -> Void
    var onSelect: ((ServerInfo) -> Void)? = nil
    
    var body: some View {
        Button {
            if let onSelect = onSelect {
                onSelect(server)
            } else {
                serverManager.selectedServerID = server.id
            }
        } label: {
            Label("Select", systemImage: "checkmark.circle")
        }
        .disabled(server.id == serverManager.selectedServerID)
        
        Button {
            onEdit(server)
        } label: {
            Label("Edit...", systemImage: "pencil")
        }
        
        Divider()
        
        Button(role: .destructive) {
            onDelete(server)
        } label: {
            Label("Delete...", systemImage: "trash")
        }
    }
}
