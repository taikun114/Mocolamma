import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// モデルに対する各種操作（ロード、アンロード、モデル名コピー、削除など）を提供する共通メニューコンテンツです。
/// コンテキストメニューおよびツールバーのアクションメニューで共通して使用されます。
struct ModelActionMenuContent: View {
    let model: OllamaModel
    var executor: CommandExecutor
    var isActionsDisabled: Bool = false
    var onCustomKeepAlive: (OllamaModel) -> Void
    var onDelete: (OllamaModel) -> Void
    var onCopy: ((String) -> Void)? = nil
    var onError: ((String) -> Void)? = nil
    
    private var copyIconName: String {
        SFSymbol.copy
    }
    
    var body: some View {
        Menu {
            Button("Load with Default Time") {
                loadWithTime(nil)
            }
            .disabled(isActionsDisabled)
            
            Divider()
            
            Group {
                Button(LocalizedStringKey(KeepAliveOption.m1.rawValue)) { loadWithTime("1m") }
                Button(LocalizedStringKey(KeepAliveOption.m3.rawValue)) { loadWithTime("3m") }
                Button(LocalizedStringKey(KeepAliveOption.m5.rawValue)) { loadWithTime("5m") }
                Button(LocalizedStringKey(KeepAliveOption.m10.rawValue)) { loadWithTime("10m") }
                Button(LocalizedStringKey(KeepAliveOption.m15.rawValue)) { loadWithTime("15m") }
                Button(LocalizedStringKey(KeepAliveOption.m30.rawValue)) { loadWithTime("30m") }
                Button(LocalizedStringKey(KeepAliveOption.h1.rawValue)) { loadWithTime("1h") }
                Button(LocalizedStringKey(KeepAliveOption.indefinite.rawValue)) { loadWithTime("-1") }
            }
            .disabled(isActionsDisabled)
            
            Divider()
            
            Button("Custom...") {
                onCustomKeepAlive(model)
            }
            .disabled(isActionsDisabled)
        } label: {
            Label("Load Model", systemImage: "tray.and.arrow.down")
        }
        
        Button("Unload Model", systemImage: "tray.and.arrow.up") {
            Task {
                await executor.unloadModel(modelName: model.name)
            }
        }
        .disabled(isActionsDisabled || isModelNotLoaded)
        
        Divider()
        
        Button {
            copyModelName()
        } label: {
            Label("Copy Model Name", systemImage: copyIconName)
        }
        
        Button(role: .destructive) {
            onDelete(model)
        } label: {
            Label("Delete...", systemImage: "trash")
        }
        .disabled(isActionsDisabled)
    }
    
    // モデルがロード状態でないか判定
    private var isModelNotLoaded: Bool {
        !executor.runningModels.contains(where: { $0.name == model.name || $0.name == "\(model.name):latest" })
    }
    
    private func copyModelName() {
        if let onCopy = onCopy {
            onCopy(model.name)
        } else {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(model.name, forType: .string)
            #else
            UIPasteboard.general.string = model.name
            #endif
        }
    }
    
    private func loadWithTime(_ time: String?) {
        Task {
            let keepAlive: JSONValue?
            if let time = time {
                if time == "-1" {
                    keepAlive = .int(-1)
                } else {
                    keepAlive = .string(time)
                }
            } else {
                keepAlive = nil
            }
            
            let success = await executor.loadModel(modelName: model.name, keepAlive: keepAlive, ignoreTimeout: true)
            if !success {
                if let errorText = parseError(from: executor.output) {
                    await MainActor.run {
                        onError?(errorText)
                    }
                }
            }
        }
    }
    
    private func parseError(from output: String, replaceNewline: Bool = true) -> String? {
        if let data = output.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? String {
            return replaceNewline ? err.replacingOccurrences(of: "\n", with: " ") : err
        }
        if output.lowercased().contains("error") {
            return replaceNewline ? output.replacingOccurrences(of: "\n", with: " ") : output
        }
        return nil
    }
}
