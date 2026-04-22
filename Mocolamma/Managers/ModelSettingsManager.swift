import SwiftUI
import Observation

/// モデルの並び順に関する設定で使用される並び替え基準の定義です。
enum ModelSortCriterion: String, CaseIterable, Identifiable {
    /// モデルリストの並び順
    case modelList = "Model List Order"
    /// 番号
    case number = "Number"
    /// 名前
    case name = "Name"
    /// サイズ
    case size = "Size"
    /// 変更日
    case date = "Modified At"
    /// ステータス
    case status = "Status"
    
    var id: String { self.rawValue }
    
    /// 各基準に対応するアイコン名を返します。
    var iconName: String {
        switch self {
        case .modelList: return "tray.full"
        case .number: return "textformat.numbers"
        case .name: return "textformat"
        case .size: return "internaldrive"
        case .date: return "calendar"
        case .status: return "info.circle"
        }
    }
    
    /// ローカライズされた表示名を返します。
    var localizedName: String {
        switch self {
        case .modelList: return String(localized: "Model List Order")
        case .number: return String(localized: "Number")
        case .name: return String(localized: "Name")
        case .size: return String(localized: "Size")
        case .date: return String(localized: "Modified At")
        case .status: return String(localized: "Status")
        }
    }
}

/// モデルの並び順に関する設定で使用される昇順・降順の定義です。
enum ModelSortOrder: String, CaseIterable, Identifiable {
    /// 昇順
    case ascending = "Ascending"
    /// 降順
    case descending = "Descending"
    
    var id: String { self.rawValue }
    
    /// 各順序に対応するアイコン名を返します。
    var iconName: String {
        switch self {
        case .ascending: return "chevron.down.2"
        case .descending: return "chevron.up.2"
        }
    }
    
    /// ローカライズされた表示名を返します。
    var localizedName: String {
        switch self {
        case .ascending: return String(localized: "Ascending")
        case .descending: return String(localized: "Descending")
        }
    }
}

/// モデルの並び順に関する設定を管理するマネージャー。
@Observable
final class ModelSettingsManager {
    static let shared = ModelSettingsManager()
    
    /// チャットと画像生成画面に表示されるモデルの順番に、モデルリストで指定した並び順を使用するかどうか。
    var useModelListOrder: Bool {
        didSet {
            UserDefaults.standard.set(useModelListOrder, forKey: "useModelListOrder")
        }
    }
    
    /// チャット画面でのモデルの並び替え基準。
    var chatSortCriterion: ModelSortCriterion {
        didSet {
            UserDefaults.standard.set(chatSortCriterion.rawValue, forKey: "chatSortCriterion")
        }
    }
    
    /// チャット画面でのモデルの並び順（昇順・降順）。
    var chatSortOrder: ModelSortOrder {
        didSet {
            UserDefaults.standard.set(chatSortOrder.rawValue, forKey: "chatSortOrder")
        }
    }
    
    /// 画像生成画面でのモデルの並び替え基準。
    var imageSortCriterion: ModelSortCriterion {
        didSet {
            UserDefaults.standard.set(imageSortCriterion.rawValue, forKey: "imageSortCriterion")
        }
    }
    
    /// 画像生成画面でのモデルの並び順（昇順・降順）。
    var imageSortOrder: ModelSortOrder {
        didSet {
            UserDefaults.standard.set(imageSortOrder.rawValue, forKey: "imageSortOrder")
        }
    }
    
    /// モデルリスト画面での現在のソート順。
    var modelListSortOrder: [KeyPathComparator<OllamaModel>] {
        didSet {
            // メモ: KeyPathComparator はそのままでは UserDefaults に保存できないため、
            // 現時点ではアプリ実行中のメモリ保持のみとしています（セッション内での同期用）。
            // 永続化が必要な場合は、基準（criterion）や順序（order）を別途保存する必要があります。
        }
    }
    
    private init() {
        // デフォルトのソート順（番号昇順）
        self.modelListSortOrder = [KeyPathComparator(\.originalIndex, order: .forward)]
        
        // デフォルトはオン
        self.useModelListOrder = UserDefaults.standard.object(forKey: "useModelListOrder") as? Bool ?? true
        
        // チャット設定の読み込み
        if let chatCrit = UserDefaults.standard.string(forKey: "chatSortCriterion"),
           let criterion = ModelSortCriterion(rawValue: chatCrit) {
            self.chatSortCriterion = criterion
        } else {
            self.chatSortCriterion = .modelList
        }
        
        if let chatOrder = UserDefaults.standard.string(forKey: "chatSortOrder"),
           let order = ModelSortOrder(rawValue: chatOrder) {
            self.chatSortOrder = order
        } else {
            self.chatSortOrder = .ascending
        }
        
        // 画像生成設定の読み込み
        if let imageCrit = UserDefaults.standard.string(forKey: "imageSortCriterion"),
           let criterion = ModelSortCriterion(rawValue: imageCrit) {
            self.imageSortCriterion = criterion
        } else {
            self.imageSortCriterion = .modelList
        }
        
        if let imageOrder = UserDefaults.standard.string(forKey: "imageSortOrder"),
           let order = ModelSortOrder(rawValue: imageOrder) {
            self.imageSortOrder = order
        } else {
            self.imageSortOrder = .ascending
        }
    }
    
    /// 指定された画面（チャットまたは画像生成）で使用するソート順を返します。
    func sortOrder(forChat: Bool) -> [KeyPathComparator<OllamaModel>] {
        if useModelListOrder {
            // モデルリストの並び順を使用する設定がオンの場合は、モデルリストの現在のソート順を返す
            return modelListSortOrder
        } else {
            // オフの場合は、個別に設定された並び順を返す
            let criterion = forChat ? chatSortCriterion : imageSortCriterion
            let order = forChat ? chatSortOrder : imageSortOrder
            let foundationOrder: Foundation.SortOrder = (order == .ascending) ? .forward : .reverse
            
            switch criterion {
            case .modelList:
                return modelListSortOrder.map {
                    var comparator = $0
                    comparator.order = foundationOrder
                    return comparator
                }
            case .number:
                return [KeyPathComparator(\.originalIndex, order: foundationOrder)]
            case .name:
                return [KeyPathComparator(\.name, order: foundationOrder)]
            case .size:
                return [KeyPathComparator(\.comparableSize, order: foundationOrder)]
            case .date:
                return [KeyPathComparator(\.comparableModifiedDate, order: foundationOrder)]
            case .status:
                return [KeyPathComparator(\.statusWeight, order: foundationOrder)]
            }
        }
    }
}
