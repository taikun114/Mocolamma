import Foundation
import SwiftUI
import Combine
import Observation

@Observable @preconcurrency @MainActor
class CommandExecutor: NSObject, URLSessionDelegate, URLSessionDataDelegate {
    var output: String = ""
    var isRunning: Bool = false
    var pullHttpErrorTriggered: Bool = false
    var pullHttpErrorMessage: String = ""
    var models: [OllamaModel] = []
    var apiConnectionError: Bool = false
    var specificConnectionErrorMessage: String?
        var chatMessages: [ChatMessage] = []
        var chatInputText: String = ""
        var chatInputImages: [ChatInputImage] = []
        var isChatStreaming: Bool = false
        
        var imageMessages: [ChatMessage] = []
        var imageInputImages: [ChatInputImage] = []
        var isImageStreaming: Bool = false
        var previewImage: PlatformImage? = nil
    var successfullyDownloadedIDs: Set<UUID> = []
    var successfullyCopiedIDs: Set<UUID> = []
    var runningModels: [OllamaRunningModel] = []
    var isDraggingFile: Bool = false
    
    // システム全体のドラッグ監視用 (deinitからアクセスできるようnonisolatedに)
    @ObservationIgnored
    nonisolated(unsafe) private var dragMonitoringTimer: Timer?
    @ObservationIgnored
    private var lastDragPasteboardChangeCount: Int = -1
    @ObservationIgnored
    private var dragResetTask: Task<Void, Never>?
    @ObservationIgnored
    private var lastDragActivityTime: Date = Date.distantPast
    
    // モデルプル時の進捗状況
    var isPulling: Bool = false
    var isPullingErrorHold: Bool = false
    var pullHasError: Bool = false
    var pullStatus: String = "Preparing..." // プルステータス: 準備中。
    var pullProgress: Double = 0.0 // 0.0 から 1.0
    var pullTotal: Int64 = 0 // 合計バイト数
    var pullCompleted: Int64 = 0 // 完了したバイト数
    var pullSpeedBytesPerSec: Double = 0.0 // 現在のダウンロード速度 (B/s)
    var pullETARemaining: TimeInterval = 0 // 残り推定時間(秒)
    var lastPulledModelName: String = "" // 最後にプルリクエストを送ったモデル名
    private var urlSession: URLSession!
    private var connectionCheckSession: URLSession! // 接続確認専用（30秒固定）
    private var pullTask: URLSessionDataTask?
    private var pullLineBuffer = "" // 不完全なJSON行を保持する文字列バッファ
    private var lastSpeedSampleTime: Date? // 速度算出用の前回サンプル時刻
    private var lastSpeedSampleCompleted: Int64 = 0 // 速度算出用の前回完了バイト
    private var pullStatusUpdateTimer: Timer? // プルステータスの更新タイマー
    private var lastPullStatusUpdate: Date = Date(timeIntervalSince1970: 0) // 最後にプルステータスを更新した時間
    private var pendingPullStatus: String? // 更新待機中のプルステータス
    private var pendingPullTotal: Int64 = 0 // 更新待機中の合計バイト数
    private var pendingPullCompleted: Int64 = 0 // 更新待機中の完了バイト数
    private var pendingPullProgress: Double = 0.0 // 更新待機中の進捗
    private let pullStatusUpdateInterval: TimeInterval = 0.033 // プルステータスの更新間隔（秒）: 約30fps
    private var chatContinuations: [URLSessionTask: (continuation: AsyncThrowingStream<ChatResponseChunk, Error>.Continuation, isStreaming: Bool)] = [:]
    private var chatLineBuffers: [URLSessionTask: String] = [:]
    private var imageContinuations: [URLSessionTask: (continuation: AsyncThrowingStream<ImageGenerationResponseChunk, Error>.Continuation, isStreaming: Bool)] = [:]
    private var imageLineBuffers: [URLSessionTask: String] = [:]
    private var currentChatTask: URLSessionDataTask? // 現在のチャットタスクを保持
    private var currentImageTask: URLSessionDataTask? // 現在の画像生成タスクを保持
    
    // Ollama APIのベースURL
    var apiBaseURL: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - デモモード用
    private var hasDownloadedDemoModel: Bool = false
    
    // MARK: - モデル情報キャッシュ
    private var modelInfoCache: [String: OllamaShowResponse] = [:]
    
    // isChatStreamingを更新する関数
    func updateIsChatStreaming() {
        isChatStreaming = chatMessages.firstIndex { $0.isStreaming } != nil
    }
    
    // isImageStreamingを更新する関数
    func updateIsImageStreaming() {
        isImageStreaming = imageMessages.firstIndex { $0.isStreaming } != nil
    }
    
    /// システム全体のファイルドラッグ状態を監視するためのタイマーをセットアップします。
    private func setupDragMonitoring() {
        #if os(macOS)
        // ドラッグ用ペーストボードの監視を開始 (0.1秒ごとにチェック)
        dragMonitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                
                let pb = NSPasteboard(name: .drag)
                let currentChangeCount = pb.changeCount
                
                // ペーストボードの内容が変更された場合
                if currentChangeCount != self.lastDragPasteboardChangeCount {
                    self.lastDragPasteboardChangeCount = currentChangeCount
                    
                    // ファイルが含まれており、かつそれが画像として読み込み可能か確認
                    let hasFiles = pb.types?.contains(.fileURL) == true || 
                                 pb.types?.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")) == true
                    
                    let hasImages = pb.canReadObject(forClasses: [PlatformImage.self], options: nil)
                    
                    if hasFiles && hasImages {
                        self.startDragging()
                    }
                }
                
                // マウスボタンが離されている場合は、ドラッグ終了とみなす
                // NSEvent.pressedMouseButtons はグローバルな状態を取得でき、権限も不要
                if NSEvent.pressedMouseButtons == 0 {
                    if self.isDraggingFile {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.isDraggingFile = false
                        }
                    }
                }
            }
        }
        #endif
    }
    
    /// ドラッグが開始されたことを通知します。
    func startDragging() {
        lastDragActivityTime = Date()
        if !isDraggingFile {
            withAnimation(.easeInOut(duration: 0.2)) {
                isDraggingFile = true
            }
        }
        
        // ウォッチドッグタスクの開始
        startDragWatchdog()
    }
    
    /// ドラッグのアクティビティ（更新）を通知します。
    func notifyDragActivity() {
        lastDragActivityTime = Date()
    }
    
    /// ドラッグが継続しているか監視し、信号が途絶えたらリセットします。
    private func startDragWatchdog() {
        dragResetTask?.cancel()
        dragResetTask = Task {
            while !Task.isCancelled {
                // 100ミリ秒ごとにチェック
                try? await Task.sleep(nanoseconds: 100_000_000)
                
                if !Task.isCancelled {
                    let now = Date()
                    // 最終アクティビティから2.0秒以上経過していたら終了とみなす
                    // iOSでは指を止めている間にイベントが途切れることがあるため、長めに設定
                    if now.timeIntervalSince(lastDragActivityTime) > 2.0 {
                        await MainActor.run {
                            if self.isDraggingFile {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    self.isDraggingFile = false
                                }
                            }
                        }
                        break
                    }
                }
            }
        }
    }
    
    /// ドラッグが終了した（またはビューから外れた）ことを通知します。
    func stopDragging(immediate: Bool = false) {
        if immediate {
            dragResetTask?.cancel()
            isDraggingFile = false
            return
        }
        // 非即時の場合はウォッチドッグに任せる
    }
    
    deinit {
        #if os(macOS)
        dragMonitoringTimer?.invalidate()
        dragMonitoringTimer = nil
        #endif
    }
    
    /// デモサーバーかどうかを判定します
    private func isDemoServer() -> Bool {
        guard let host = apiBaseURL else { return false }
        return host == "demo-mode"
    }
    
    /// CommandExecutorのイニシャライザ。ServerManagerのインスタンスを受け取り、APIベースURLを監視します。
    /// - Parameter serverManager: サーバーリストと選択状態を管理するServerManagerのインスタンス。
    init(serverManager: ServerManager) {
        // 初期化時にServerManagerから現在のホストURLを設定
        self.apiBaseURL = serverManager.currentServerHost
        super.init()
        // デリゲートキューをnilに設定し、デリゲートメソッドがバックグラウンドスレッドで実行されるようにします
        let configuration = URLSessionConfiguration.default
        let opt = APITimeoutManager.shared.currentOption
        configuration.timeoutIntervalForRequest = opt.requestTimeoutUntilFirstByte
        configuration.timeoutIntervalForResource = opt.overallResourceTimeout
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        
        // 接続確認専用セッション（30秒固定）
        let checkConfig = URLSessionConfiguration.default
        checkConfig.timeoutIntervalForRequest = 30.0
        checkConfig.timeoutIntervalForResource = 30.0
        connectionCheckSession = URLSession(configuration: checkConfig)
        
        // ドラッグ監視のセットアップ (ポーリング方式)
        setupDragMonitoring()
        
        // ServerManagerのcurrentServerHostの変更を監視し、apiBaseURLを更新
        serverManager.$servers
            .map { servers in
                // serversリストが変更された場合、selectedServerIDに基づき新しいcurrentServerHostを計算
                if let selectedID = serverManager.selectedServerID,
                   let selectedServer = servers.first(where: { $0.id == selectedID }) {
                    return selectedServer.host
                }
                return nil
            }
            .sink { [weak self] host in
                self?.apiBaseURL = host
            }
            .store(in: &cancellables)
        
        serverManager.$selectedServerID
            .compactMap { selectedID in
                // selectedIDが変更された場合、対応するサーバーのホストを返す
                serverManager.servers.first(where: { $0.id == selectedID })?.host
            }
            .sink { [weak self] host in
                self?.apiBaseURL = host
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.addObserver(forName: .apiTimeoutChanged, object: nil, queue: .main) { [weak self] note in
            guard let self = self else { return }
            let opt = APITimeoutManager.shared.currentOption
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = opt.requestTimeoutUntilFirstByte
            config.timeoutIntervalForResource = opt.overallResourceTimeout
            self.urlSession.invalidateAndCancel()
            self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        }
    }
    
    /// Ollama APIからモデルリストを取得します
    func fetchOllamaModelsFromAPI() async {
        if isDemoServer() {
            // デモサーバーの場合、固定のデモデータを返す
            self.output = NSLocalizedString("Fetching models from demo server...", comment: "デモサーバーからモデルリストを取得中のメッセージ。")
            self.isRunning = true
            defer { self.isRunning = false }
            
            // 1分前、3分前、5分前、7分前の日付をISO 8601形式で計算
            let oneMinuteAgo = Date().addingTimeInterval(-60) // 1分前
            let threeMinutesAgo = Date().addingTimeInterval(-180) // 3分前
            let fiveMinutesAgo = Date().addingTimeInterval(-300) // 5分前
            let sevenMinutesAgo = Date().addingTimeInterval(-420) // 7分前
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            // デモデータのモデルリストを設定
            let demoModelDetails = OllamaModelDetails(
                parent_model: "",
                format: "gguf",
                family: "demo",
                families: ["demo"],
                parameter_size: "0B",
                quantization_level: "Q4_K_M",
                context_length: 2048
            )
            
            let demoImageDetails = OllamaModelDetails(
                parent_model: "",
                format: "safetensors",
                family: "demo",
                families: nil,
                parameter_size: "0B",
                quantization_level: "FP4",
                context_length: nil
            )
            
            var demoModels: [OllamaModel] = []
            
            // ダウンロードシミュレーションが完了している場合、リストに追加
            if hasDownloadedDemoModel {
                let downloadedDemoModel = OllamaModel(
                    name: "demo-dl:0b",
                    model: "demo-dl:0b",
                    modifiedAt: formatter.string(from: oneMinuteAgo),
                    size: 0,
                    digest: "0000000000dl",
                    details: demoModelDetails,
                    capabilities: ["completion", "tools", "thinking", "vision"],
                    originalIndex: 0
                )
                demoModels.append(downloadedDemoModel)
                hasDownloadedDemoModel = false // 一度表示したらフラグをリセット
            }
            
            let demoModel1 = OllamaModel(
                name: "demo:0b",
                model: "demo:0b",
                modifiedAt: formatter.string(from: threeMinutesAgo),
                size: 0,
                digest: "000000000000",
                details: demoModelDetails,
                capabilities: ["completion"],
                originalIndex: 0
            )
            let demoModel2 = OllamaModel(
                name: "demo2:0b",
                model: "demo2:0b",
                modifiedAt: formatter.string(from: fiveMinutesAgo),
                size: 0,
                digest: "000000000001",
                details: demoModelDetails,
                capabilities: ["completion"],
                originalIndex: 1
            )
            let demoModel3 = OllamaModel(
                name: "demo-image:0b",
                model: "demo-image:0b",
                modifiedAt: formatter.string(from: sevenMinutesAgo),
                size: 0,
                digest: "000000000002",
                details: demoImageDetails,
                capabilities: ["image"],
                originalIndex: 2
            )
            
            demoModels.append(contentsOf: [demoModel1, demoModel2, demoModel3])
            
            self.models = demoModels.enumerated().map { (index, model) in
                var mutableModel = model
                mutableModel.originalIndex = index
                return mutableModel
            }
            
            let successMessage = String(format: NSLocalizedString("Successfully fetched models from demo server. Total: %d", comment: "デモサーバーからモデル情報を取得した場合のメッセージ。"), self.models.count)
            self.output = successMessage
            self.apiConnectionError = false // 成功時はエラーなし
            return
        }
        
        guard let apiBaseURL = self.apiBaseURL else {
            // apiBaseURLがnilの場合、何もしない
            print("Ollama API base URL is not set. Skipping model list retrieval.")
            self.output = NSLocalizedString("Error: No Ollama server selected.", comment: "Ollamaサーバーが選択されていないときのエラーメッセージ。")
            self.apiConnectionError = true
            return
        }
        print("Fetching model list from Ollama API at \(apiBaseURL)...")
        // UI更新はメインアクターで行います
        self.output = String(format: NSLocalizedString("Fetching models from API (%@)...", comment: "Ollamaサーバーからモデルリストを取得中のメッセージ。API (サーバーURL)...。"), apiBaseURL)
        try? await Task.sleep(nanoseconds: 100_000_000)
        self.isRunning = true
        self.apiConnectionError = false // 新しいフェッチの前にエラー状態をリセット
        
        defer {
            self.isRunning = false
        }
        
        let scheme = apiBaseURL.hasPrefix("https://") ? "https" : "http"
        let hostWithoutScheme = apiBaseURL.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        guard let url = URL(string: "\(scheme)://\(hostWithoutScheme)/api/tags") else {
            self.output = NSLocalizedString("Error: Invalid API URL.", comment: "無効なAPI URLのエラーメッセージ。")
            self.models = [] // エラー時もモデルリストをクリア
            self.apiConnectionError = true // API接続エラーを設定
            return
        }
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.output = NSLocalizedString("API Error: Unknown response type.", comment: "不明なAPIレスポンスタイプのエラーメッセージ。")
                print("API Error: Unknown response type.")
                self.models = [] // エラー時もモデルリストをクリア
                self.apiConnectionError = true // API接続エラーを設定
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                let statusMessage = String(format: NSLocalizedString("API Error: HTTP Status Code %d", comment: "HTTPステータスコードのエラーメッセージ。HTTPステータスコード。"), httpResponse.statusCode)
                self.output = statusMessage
                print("API Error: HTTP status code \(httpResponse.statusCode).")
                if let errorString = String(data: data, encoding: .utf8) {
                    print("API Error Response: \(errorString)")
                }
                self.models = [] // エラー時もモデルリストをクリア
                self.apiConnectionError = true // API接続エラーを設定
                return
            }
            
            print("Attempting to decode. Data size: \(data.count) bytes. First 10 bytes: \(data.prefix(10).map { String(format: "%02x", $0) }.joined())...")
            
            let apiResponse = try JSONDecoder().decode(OllamaAPIModelsResponse.self, from: data)
            let initialModels = apiResponse.models
            
            // 各モデルの詳細情報（capabilitiesなど）を並列で取得
            self.models = await withTaskGroup(of: (Int, OllamaModel).self) { group in
                for (index, model) in initialModels.enumerated() {
                    group.addTask {
                        var detailedModel = model
                        detailedModel.originalIndex = index
                        if let info = await self.fetchModelInfo(modelName: model.name) {
                            detailedModel.capabilities = info.capabilities
                            // 詳細情報（/api/show）のdetailsの方が正確（画像モデルなど）なため、常に上書きする
                            detailedModel.details = info.details
                        }
                        return (index, detailedModel)
                    }
                }
                
                var updatedModels: [(Int, OllamaModel)] = []
                for await result in group {
                    updatedModels.append(result)
                }
                // 元の順序を維持してソート
                return updatedModels.sorted(by: { $0.0 < $1.0 }).map { $0.1 }
            }
            
            let successMessage = String(format: NSLocalizedString("Successfully fetched models. Total: %d", comment: "Ollamaサーバー上からモデル情報を取得することができた場合のメッセージ。合計モデル数。"), self.models.count)
            self.output = successMessage
            print("Successfully retrieved models. Total: \(self.models.count)")
            self.apiConnectionError = false // 成功時はエラーなし
            
            // 実行中のモデルリストも更新
            _ = await self.fetchRunningModels()
            
        } catch let decodingError as DecodingError {
            self.output = NSLocalizedString("API Decode Error: ", comment: "APIデコードエラーのプレフィックスメッセージ。") + decodingError.localizedDescription
            print("API Decoding Error: \(decodingError.localizedDescription)")
            self.models = [] // デコードエラー時もモデルリストをクリア
            self.apiConnectionError = true // API接続エラーを設定
            
            switch decodingError {
            case .keyNotFound(let key, let context):
                print("DecodingError.keyNotFound: Key '\(key.stringValue)' not found. \(context.debugDescription)")
                print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .typeMismatch(let type, let context):
                print("DecodingError.typeMismatch: Type '\(type)' mismatch. \(context.debugDescription)")
                print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .valueNotFound(let type, let context):
                print("DecodingError.valueNotFound: Value of type '\(type)' not found. \(context.debugDescription)")
                print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .dataCorrupted(let context):
                print("DecodingError.dataCorrupted: Data corrupted. \(context.debugDescription)")
                print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            @unknown default:
                print("Unknown DecodingError: \(decodingError.localizedDescription)")
            }
            
        } catch {
            self.output = NSLocalizedString("API Request Error: ", comment: "APIリクエストエラーのプレフィックスメッセージ。") + error.localizedDescription
            print("API Request Error (Other): \(error.localizedDescription)")
            self.models = [] // その他のエラー時もモデルリストをクリア
            self.apiConnectionError = true // API接続エラーを設定
        }
    }
    
    /// モデルをダウンロードします
    func pullModel(modelName: String) {
        guard let apiBaseURL = self.apiBaseURL else {
            print("Ollama API base URL is not set. Skipping model pull.")
            self.output = NSLocalizedString("Error: No Ollama server selected.", comment: "Ollamaサーバーが選択されていない時にモデルのダウンロードを行おうとした場合のエラーメッセージ。")
            self.isPulling = false
            return
        }
        
        // デモモードでのダウンロードシミュレーション
        if isDemoServer() && (modelName == "demo-dl" || modelName == "demo-dl:0b") {
            simulateDemoDownload(modelName: "demo-dl:0b")
            return
        }
        
        print("Attempting to pull model \(modelName) from \(apiBaseURL)")
        // UI更新はメインアクターで行います
        self.output = String(format: NSLocalizedString("Downloading model '%@' from %@...", comment: "Ollamaサーバー上でモデルをダウンロード中に表示されるメッセージ。モデル名 from サーバーURL"), modelName, apiBaseURL)
        self.isPulling = true
        self.isPullingErrorHold = false
        self.pullHasError = false
        self.pullStatus = NSLocalizedString("Preparing...", comment: "Ollamaサーバー上でモデルダウンロードを開始したときの準備中に表示されるメッセージ。")
        self.pullProgress = 0.0
        self.pullTotal = 0
        self.pullCompleted = 0
        self.pullSpeedBytesPerSec = 0.0
        self.pullETARemaining = 0
        self.lastSpeedSampleTime = nil
        self.lastSpeedSampleCompleted = 0
        self.lastPulledModelName = modelName // 最後にプルリクエストを送ったモデル名を更新
        
        // プル処理用の特別なURLセッションを作成（タイムアウトを無制限に設定）
        let pullConfig = URLSessionConfiguration.default
        pullConfig.timeoutIntervalForRequest = TimeInterval(3600) // 1時間のタイムアウト（実質無制限）
        pullConfig.timeoutIntervalForResource = TimeInterval(86400) // 24時間のタイムアウト（実質無制限）
        let pullSession = URLSession(configuration: pullConfig, delegate: self, delegateQueue: nil)
        
        let scheme = apiBaseURL.hasPrefix("https://") ? "https" : "http"
        let hostWithoutScheme = apiBaseURL.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        guard let url = URL(string: "\(scheme)://\(hostWithoutScheme)/api/pull") else {
            self.output = NSLocalizedString("Error: Invalid API URL for pull.", comment: "Ollamaサーバー上でモデルをダウンロードしようとした際に、APIURLが無効だった場合に表示されるエラーメッセージ。")
            self.isPulling = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["model": modelName, "stream": true]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            self.output = NSLocalizedString("Error: Failed to serialize pull request body: ", comment: "Ollamaサーバー上でモデルをダウンロードしようとした際に、リクエストボディのシリアライズに失敗した場合のエラーメッセージ。") + error.localizedDescription
            self.isPulling = false
            return
        }
        
        pullTask?.cancel()
        pullTask = pullSession.dataTask(with: request)
        pullTask?.resume()
    }
    
    /// デモモード用のダウンロードシミュレーションを実行します
    private func simulateDemoDownload(modelName: String) {
        Task {
            self.isPulling = true
            self.isPullingErrorHold = false
            self.pullHasError = false
            self.lastPulledModelName = modelName
            let totalSize: Int64 = 708439456
            
            // 1. Preparing (1s) - ログに基づき 488/488 バイトで開始
            self.pullStatus = NSLocalizedString("Preparing...", comment: "準備中")
            self.pullTotal = 488
            self.pullCompleted = 488
            self.pullProgress = 1.0
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            // 2. Pulling manifest (1s) - 488 / 合計サイズ
            self.pullStatus = "pulling manifest"
            self.pullTotal = totalSize
            self.pullCompleted = 488
            self.pullProgress = 0.0
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            // 3. Main Model File: pulling c0ffee10aded (45s)
            self.pullStatus = "pulling c0ffee10aded"
            let startTime = Date()
            let duration: TimeInterval = 45.0
            
            while Date().timeIntervalSince(startTime) < duration {
                let elapsed = Date().timeIntervalSince(startTime)
                let progress = elapsed / duration
                self.pullProgress = progress
                self.pullCompleted = Int64(Double(totalSize) * progress)
                self.pullSpeedBytesPerSec = Double(totalSize) / duration
                self.pullETARemaining = duration - elapsed
                
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1sごとに更新
            }
            
            // 4. pulling c0ffeef11100 (2s)
            self.pullStatus = "pulling c0ffeef11100"
            self.pullProgress = 1.0
            self.pullCompleted = totalSize
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            // 5. pulling c0ffeef11101 (2s)
            self.pullStatus = "pulling c0ffeef11101"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            // 6. verifying sha256 digest (10s)
            self.pullStatus = "verifying sha256 digest"
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            
            // 完了処理
            self.hasDownloadedDemoModel = true
            self.pullProgress = 1.0
            self.pullStatus = NSLocalizedString("Completed", comment: "完了")
            self.isPulling = false
            
            await fetchOllamaModelsFromAPI()
        }
    }
    
    /// モデルを削除します
    func deleteModel(modelName: String) async {
        guard let apiBaseURL = self.apiBaseURL else {
            print("Ollama API base URL is not set. Skipping model deletion.")
            self.output = NSLocalizedString("Error: No Ollama server selected.", comment: "Ollamaサーバーからモデルを削除しようとした際にモデルが選択されていなかった場合に表示されるイランメッセージ。")
            return
        }
        
        // デモモードでの削除（再ダウンロードを可能にするためにリストを更新するだけ）
        if isDemoServer() && modelName == "demo-dl:0b" {
            await self.fetchOllamaModelsFromAPI()
            return
        }
        
        print("Attempting to delete model \(modelName) from \(apiBaseURL)")
        // UI更新はメインアクターで行います
        self.output = String(format: NSLocalizedString("Deleting model '%@' from %@...", comment: "Ollamaサーバーからモデルを削除しているときに表示されるメッセージ。モデル名 from サーバーURL。"), modelName, apiBaseURL)
        self.isRunning = true
        
        defer { self.isRunning = false }
        
        let scheme = apiBaseURL.hasPrefix("https://") ? "https" : "http"
        let hostWithoutScheme = apiBaseURL.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        guard let url = URL(string: "\(scheme)://\(hostWithoutScheme)/api/delete") else {
            self.output = NSLocalizedString("Error: Invalid API URL for delete.", comment: "削除用API URLが無効な場合のエラーメッセージ。")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = ["model": modelName]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            self.output = NSLocalizedString("Error: Failed to serialize request body: ", comment: "リクエストボディのシリアライズ失敗のエラーメッセージ。") + error.localizedDescription
            return
        }
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.output = NSLocalizedString("Delete Error: Unknown response type.", comment: "Ollamaサーバーからモデルを削除しようとした時、不明なレスポンスタイプが返ってきた場合のエラーメッセージ。")
                print("Deletion Error: Unknown response type.")
                return
            }
            
            if httpResponse.statusCode == 200 {
                self.output = String(format: NSLocalizedString("Successfully deleted model '%@' from %@.", comment: "Ollamaサーファーからモデルを削除することに成功した場合のメッセージ。モデル名 from サーバーURL。"), modelName, apiBaseURL)
                print("Successfully deleted model '\(modelName)' from \(apiBaseURL).")
                await self.fetchOllamaModelsFromAPI() // メインアクターで実行されるasync関数なので直接呼び出し可能です
                
            } else if httpResponse.statusCode == 404 {
                self.output = String(format: NSLocalizedString("Delete Error: Model '%@' not found (404 Not Found) on %@.", comment: "Ollamaサーバーからモデルを削除しようとしたとき、削除しようとしているモデルがサーバー上に見つからない場合のエラーメッセージ。モデル名 not found (404 Not Found) on サーバーURL。"), modelName, apiBaseURL)
                print("Deletion Error: Model '\(modelName)' not found at \(apiBaseURL) (404).")
            } else {
                let errorString = String(data: data, encoding: .utf8) ?? NSLocalizedString("No data available", comment: "データが得られなかったときのメッセージ。")
                let errorMessage = String(format: NSLocalizedString("Delete Error: HTTP Status Code %d - %@ on %@", comment: "Ollamaサーバーからモデルを削除しようとしたときのエラーメッセージ。エラーコード - エラーメッセージ on サーバーURL。"), httpResponse.statusCode, errorString, apiBaseURL)
                self.output = errorMessage
                print("Deletion Error: HTTP status code \(httpResponse.statusCode) - \(errorString) on \(apiBaseURL)")
            }
        } catch {
            self.output = NSLocalizedString("Model deletion failed: ", comment: "Ollamaサーバーからモデルの削除に失敗した場合のプレフィックスメッセージ。") + error.localizedDescription
            print("Failed to delete model: \(error.localizedDescription)")
        }
    }
    
    /// モデルをメモリからアンロードします。
    /// - Returns: 成功した場合はtrue。
    @discardableResult
    func unloadModel(modelName: String, host: String? = nil) async -> Bool {
        guard let apiBaseURL = host ?? self.apiBaseURL else {
            print("Ollama API base URL is not set. Skipping model unload.")
            return false
        }
        
        // デモモードでのアンロード（リストを空にするだけ）
        if isDemoServer() || host == "demo-mode" {
            self.runningModels = []
            return true
        }
        
        print("Attempting to unload model \(modelName) from \(apiBaseURL)")
        
        let scheme = apiBaseURL.hasPrefix("https://") ? "https" : "http"
        let hostWithoutScheme = apiBaseURL.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        guard let url = URL(string: "\(scheme)://\(hostWithoutScheme)/api/generate") else {
            print("Error: Invalid API URL for unload.")
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // keep_aliveを0に設定してアンロードを実行
        let body: [String: Any] = ["model": modelName, "keep_alive": 0]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            print("Error: Failed to serialize unload request body: \(error.localizedDescription)")
            return false
        }
        
        do {
            let (_, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("Unload Error: HTTP status code \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return false
            }
            
            print("Successfully requested to unload model '\(modelName)'.")
            // 少し待機してから更新（サーバー側での処理時間を考慮）
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            // 実行中のモデルリストを更新
            _ = await self.fetchRunningModels(host: host)
            // 通知を送ってUIをリフレッシュさせる
            NotificationCenter.default.post(name: Notification.Name("InspectorRefreshRequested"), object: nil)
            return true
            
        } catch {
            print("Model unload request failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// モデルの詳細情報を取得します
    func fetchModelInfo(modelName: String) async -> OllamaShowResponse? {
        if isDemoServer() {
            // デモサーバーの場合、固定のデモデータを返す
            print("Fetching model \(modelName) details from demo server.")
            
            // モデル名に基づいて異なるデータを返す
            let isStandardDemo = modelName == "demo:0b" || modelName == "demo2:0b" || modelName == "demo-dl:0b"
            let isDemoImage = modelName == "demo-image:0b"
            
            if isStandardDemo || isDemoImage {
                // デモモデルの情報を生成
                let modelDetails: OllamaModelDetails
                let modelInfo: [String: JSONValue]
                let capabilities: [String]
                
                if isDemoImage {
                    modelDetails = OllamaModelDetails(
                        parent_model: "",
                        format: "safetensors",
                        family: "demo",
                        families: nil,
                        parameter_size: "0B",
                        quantization_level: "FP4",
                        context_length: nil
                    )
                    modelInfo = [:] // パラメータ数、コンテキスト長、埋め込み長は無し
                    capabilities = ["image"]
                } else {
                    modelDetails = OllamaModelDetails(
                        parent_model: "",
                        format: "gguf",
                        family: "demo",
                        families: ["demo"],
                        parameter_size: "0B",
                        quantization_level: "Q4_K_M",
                        context_length: 2048
                    )
                    modelInfo = [
                        "general.parameter_count": .int(0),
                        "llama.context_length": .int(2048),
                        "llama.embedding_length": .int(2048)
                    ]
                    capabilities = ["completion", "tools", "thinking", "vision"]
                }
                
                let response = OllamaShowResponse(
                    license: #"""
                      _____         _     _     _                         
                     |_   _|__  ___| |_  | |   (_) ___ ___ _ __  ___  ___ 
                       | |/ _ \/ __| __| | |   | |/ __/ _ \ '_ \/ __|/ _ \
                       | |  __/\__ \ |_  | |___| | (_|  __/ | | \__ \  __/
                       |_|\___||___/\__| |_____|_|\___\___|_| |_|___/\___|
                                                                          
                    
                    This is a test license. In actual use, the license text included with each model
                    will be displayed here.
                    
                    --------------------------------------------------------------------------------
                    
                    Lorem ipsum dolor sit amet, consectetur adipiscing elit. Primis netus venenatis
                    litora tempor accumsan. Amet mollis ad elementum diam inceptos. Commodo mauris
                    nam sem lacinia lacinia. Quam erat fermentum purus sem ad. Et rutrum mattis
                    semper nisi phasellus. Venenatis ante feugiat gravida elementum risus.
                    
                    Scelerisque velit eget risus nisi curae. Suspendisse cum sagittis arcu vel odio.
                    Cras diam senectus fermentum vehicula viverra. Feugiat eu eros lacus class mi.
                    Dignissim porta habitant ante netus duis. Sollicitudin egestas dignissim aptent
                    orci vitae. Litora nullam tellus semper posuere mus.
                    
                    Mauris risus sit cras faucibus purus. Dictumst suscipit vitae ad commodo morbi.
                    Rutrum euismod imperdiet suscipit facilisi mattis. Quisque eros venenatis enim
                    nisl ac. Tortor mus natoque tincidunt potenti potenti. Cubilia nulla aptent
                    laoreet vivamus justo. Proin elit praesent habitasse eleifend nunc.
                    
                    Scelerisque nec nam dolor est varius. Maecenas luctus posuere aliquam id lectus.
                    Congue penatibus vitae feugiat enim pellentesque. Interdum habitasse habitasse
                    potenti dictumst sed. Mattis pulvinar malesuada lectus volutpat sociosqu. Vel
                    duis at aenean purus ridiculus. Dictumst lectus vel euismod sit molestie.
                    
                    Ridiculus vestibulum eros semper orci natoque. Luctus urna porta eleifend ligula
                    tempus. Vitae porttitor mus justo sem luctus. Ac sociis interdum ad ultricies
                    mus. Dui cras enim venenatis sed phasellus. Ac nisl massa sociosqu fermentum
                    elit. Condimentum nostra proin luctus phasellus morbi.
                    
                    Platea sapien dui fringilla dolor porttitor. Porta arcu curabitur est neque est.
                    Class id senectus arcu pulvinar auctor. Dignissim nisl lorem magna erat
                    lobortis. Ad primis mattis turpis sociosqu bibendum. Congue etiam parturient
                    inceptos sagittis ante. Sit urna est vehicula habitasse taciti.
                    
                    Morbi nam curae fermentum consectetur dictum. Diam semper nullam nisl pulvinar
                    nisi. Diam neque sit sodales laoreet nisl. Imperdiet auctor interdum congue id
                    inceptos. Orci nullam auctor elit id conubia. Morbi viverra dolor maecenas
                    nostra ullamcorper. Mauris habitasse odio porta blandit nisi.
                    
                    Suscipit velit primis egestas nascetur magnis. Vivamus penatibus posuere
                    imperdiet velit integer. Consequat eget tincidunt blandit sodales primis. Sem
                    pharetra conubia malesuada dui ad. Imperdiet urna venenatis litora cum faucibus.
                    Convallis erat class vehicula phasellus massa. Eros himenaeos fusce donec
                    quisque integer.
                    
                    Commodo fusce justo et id dui. Class tincidunt posuere natoque dictum massa.
                    Magna justo ultricies consequat non iaculis. Rutrum condimentum per mus faucibus
                    massa. Aptent lorem nec velit nunc tempor. Montes varius pharetra pharetra
                    maecenas felis. Ridiculus primis dictumst habitasse amet metus.
                    
                    Ridiculus sed facilisi velit pretium velit. Laoreet rhoncus leo adipiscing
                    sapien gravida. Ac adipiscing viverra nulla fringilla tortor. Pulvinar posuere
                    adipiscing volutpat quisque faucibus. Platea mauris maecenas neque congue
                    consectetur. Dapibus sed varius tincidunt maecenas curae. Fringilla mi donec
                    laoreet curae facilisi.
                    """#,
                    modelfile: nil,
                    parameters: nil,
                    template: nil,
                    details: modelDetails,
                    model_info: modelInfo,
                    capabilities: capabilities // ここで定義したcapabilitiesを使用
                )
                
                // キャッシュにも保存
                modelInfoCache[modelName] = response
                print("Successfully returned demo model \(modelName) details.")
                
                return response
            }
        }
        
        // キャッシュに存在すればそれを返す
        if let cachedInfo = modelInfoCache[modelName] {
            print("Fetched model \(modelName) details from cache.")
            return cachedInfo
        }
        
        print("Fetching model \(modelName) details from \(String(describing: apiBaseURL))...")
        
        guard let apiBaseURL = self.apiBaseURL else {
            print("Ollama API base URL is not set. Skipping model details retrieval.")
            return nil
        }
        print("Fetching model \(modelName) details from \(String(describing: apiBaseURL))...")
        
        let scheme = apiBaseURL.hasPrefix("https://") ? "https" : "http"
        let hostWithoutScheme = apiBaseURL.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        guard let url = URL(string: "\(scheme)://\(hostWithoutScheme)/api/show") else {
            print("Error: Invalid URL for /api/show.")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["model": modelName]
        
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            print("Error: Failed to encode request body: \(error)")
            return nil
        }
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("API Error: /api/show - HTTP status code \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            
            let apiResponse = try JSONDecoder().decode(OllamaShowResponse.self, from: data)
            print("Successfully retrieved model \(modelName) details.")
            
            // 取得した情報で、リスト内のモデル情報を更新する
            if let index = self.models.firstIndex(where: { $0.name == modelName }) {
                // detailsを更新
                if let newDetails = apiResponse.details {
                    self.models[index].details = newDetails
                }
                // capabilitiesを更新
                if let newCapabilities = apiResponse.capabilities {
                    self.models[index].capabilities = newCapabilities
                }
            }
            
            // 取得した情報をキャッシュに保存
            modelInfoCache[modelName] = apiResponse
            
            return apiResponse
            
        } catch {
            print("API Request Error: /api/show - \(error.localizedDescription)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("DecodingError.keyNotFound: Key '\(key.stringValue)' not found. \(context.debugDescription)")
                    print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .typeMismatch(let type, let context):
                    print("DecodingError.typeMismatch: Type '\(type)' mismatch. \(context.debugDescription)")
                    print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .valueNotFound(let type, let context):
                    print("DecodingError.valueNotFound: Value of type '\(type)' not found. \(context.debugDescription)")
                    print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .dataCorrupted(let context):
                    print("DecodingError.dataCorrupted: Data corrupted. \(context.debugDescription)")
                    print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                @unknown default:
                    print("Unknown DecodingError: \(decodingError.localizedDescription)")
                }
            }
            return nil
        }
    }
    
    /// 指定されたホストにOllama APIが接続可能かを確認します。
    /// - Parameter host: 接続を試みるホストURL文字列 (例: "localhost:11434")。
    /// - Returns: 接続状態を示す `ServerConnectionStatus`。
    func checkAPIConnectivity(host: String) async -> ServerConnectionStatus {
        // デモサーバーの場合は常に接続済みを返す
        if host == "demo-mode" {
            return .connected
        }
        
        let scheme = host.hasPrefix("https://") ? "https" : "http"
        let hostWithoutScheme = host.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        guard let url = URL(string: "\(scheme)://\(hostWithoutScheme)/api/tags") else {
            print("Connection check error: Invalid URL for host \(host)")
            return .unknownHost
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await connectionCheckSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    print("Connection check: Successfully connected to \(host)")
                    return .connected
                } else {
                    print("Connection check: Failed to connect to \(host) - HTTP status code: \(httpResponse.statusCode)")
                    // エラーレスポンスからエラーメッセージを取得する
                    var errorMessage: String? = nil
                    if let errorResponse = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let errorText = errorResponse["error"] as? String {
                        errorMessage = errorText
                    }
                    return .errorWithMessage(statusCode: httpResponse.statusCode, errorMessage: errorMessage)
                }
            } else {
                return .unknownHost
            }
        } catch let error as URLError {
            print("Connection check URLError to \(host): \(error.code) - \(error.localizedDescription)")
            switch error.code {
            case .timedOut:
                return .timedOut
            case .cannotFindHost, .dnsLookupFailed:
                return .unknownHost
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                let msg = NSLocalizedString("TLS error occurred. Could not establish a secure connection.", comment: "TLS接続エラー時のメッセージ。")
                return .errorWithMessage(statusCode: -1, errorMessage: msg)
            default:
                return .notConnected(statusCode: error.code.rawValue)
            }
        } catch {
            print("Connection check other error to \(host): \(error.localizedDescription)")
            return .notConnected(statusCode: -1)
        }
    }
    /// Ollamaのバージョンを取得します。
    /// - Parameter host: OllamaホストのURL。
    /// - Returns: Ollamaのバージョン文字列。
    func fetchOllamaVersion(host: String) async throws -> String {
        if host == "demo-mode" {
            // デモサーバーの場合は固定のバージョンを返す
            return "0.0.0"
        }
        
        let scheme = host.hasPrefix("https://") ? "https" : "http"
        let hostWithoutScheme = host.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        guard let url = URL(string: "\(scheme)://\(hostWithoutScheme)/api/version") else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await urlSession.data(from: url)
        let response = try JSONDecoder().decode(OllamaVersionResponse.self, from: data)
        return response.version
    }
    
    /// モデル情報キャッシュをクリアします。
    func clearModelInfoCache() {
        modelInfoCache.removeAll()
        print("Model information cache cleared.")
    }
    
    /// 現在メモリにロードされているモデル数を取得します。
    func fetchRunningModelsCount(host: String? = nil) async -> Int? {
        let base = host ?? apiBaseURL
        if base == "demo-mode" {
            // デモサーバーの場合は固定の実行中モデル数を返す
            return 1
        }
        
        guard let base = base else { return nil }
        let scheme = base.hasPrefix("https://") ? "https" : "http"
        let hostWithoutScheme = base.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        guard let url = URL(string: "\(scheme)://\(hostWithoutScheme)/api/ps") else { return nil }
        do {
            let (data, response) = try await urlSession.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            let ps = try JSONDecoder().decode(OllamaPSResponse.self, from: data)
            return ps.models.count
        } catch {
            print("Failed to retrieve /api/ps: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 現在メモリにロードされているモデルのリストを取得します。
    func fetchRunningModels(host: String? = nil) async -> [OllamaRunningModel]? {
        let base = host ?? apiBaseURL
        if base == "demo-mode" {
            // デモサーバーの場合は固定の実行中モデルを返す
            let fiveMinutesLater = Date().addingTimeInterval(300) // 5分後
            let demoRunningModels = [OllamaRunningModel(
                name: "demo:0b",
                expires_at: fiveMinutesLater,
                size_vram: 0 // 0バイト
            )]
            self.runningModels = demoRunningModels
            return demoRunningModels
        }
        
        guard let base = base else { return nil }
        let scheme = base.hasPrefix("https://") ? "https" : "http"
        let hostWithoutScheme = base.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        guard let url = URL(string: "\(scheme)://\(hostWithoutScheme)/api/ps") else { return nil }
        do {
            let (data, response) = try await urlSession.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            let ps = try JSONDecoder().decode(OllamaPSResponse.self, from: data)
            self.runningModels = ps.models
            return ps.models
        } catch {
            print("Failed to retrieve /api/ps: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Ollamaの /api/chat エンドポイントにリクエストを送信し、ストリーミングレスポンスを処理します。
    /// - Parameter chatRequest: 送信するChatRequestオブジェクト。
    /// - Returns: ChatResponseChunkのAsyncThrowingStream。
    func chat(model: String, messages: [ChatMessage], stream: Bool, useCustomChatSettings: Bool, isTemperatureEnabled: Bool, chatTemperature: Double, isContextWindowEnabled: Bool, contextWindowValue: Double, isSeedEnabled: Bool, seed: Int, repeatLastN: Int?, repeatPenalty: Double?, numPredict: Int?, topK: Int?, topP: Double?, minP: Double?, isSystemPromptEnabled: Bool, systemPrompt: String, thinkingOption: ThinkingOption, tools: [ToolDefinition]?, keepAlive: JSONValue? = nil) -> AsyncThrowingStream<ChatResponseChunk, Error> {
        if isDemoServer() {
            // デモサーバーの場合、固定のデモデータを返す
            return AsyncThrowingStream { continuation in
                Task { @MainActor in
                    // チャットストリームを開始
                    let created_at = Date()
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    
                    if stream {
                        // ストリーミングモード（stream: true）
                        
                        // チンキングオプションがONの場合、Thinkingメッセージを送信
                        if thinkingOption == .on {
                            let thinkingMessages = ["Test", "ing", ".", ".", ".  ", "Test", "ing", ".", ".", ".  ", "Test", "ing", ".", ".", ".!"]
                            
                            for thinkingMessage in thinkingMessages {
                                // 0.5秒ごとにThinkingメッセージを送信
                                try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                                
                                let responseChunk = ChatResponseChunk(
                                    model: model,
                                    createdAt: formatter.string(from: created_at),
                                    message: ChatMessage(
                                        role: "assistant",
                                        content: "",
                                        thinking: thinkingMessage
                                    ),
                                    done: false,
                                    totalDuration: nil,
                                    loadDuration: nil,
                                    promptEvalCount: nil,
                                    promptEvalDuration: nil,
                                    evalCount: nil,
                                    evalDuration: nil,
                                    doneReason: nil
                                )
                                
                                continuation.yield(responseChunk)
                            }
                        }
                        
                        let responseMessages = ["This ", "is ", "a ", "test", "!"]
                        
                        for responseMessage in responseMessages {
                            // 0.5秒ごとにレスポンスメッセージを送信
                            try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                            
                            let responseChunk = ChatResponseChunk(
                                model: model,
                                createdAt: formatter.string(from: created_at),
                                message: ChatMessage(
                                    role: "assistant",
                                    content: responseMessage
                                ),
                                done: false,
                                totalDuration: nil,
                                loadDuration: nil,
                                promptEvalCount: nil,
                                promptEvalDuration: nil,
                                evalCount: nil,
                                evalDuration: nil,
                                doneReason: nil
                            )
                            
                            continuation.yield(responseChunk)
                        }
                        
                        // 最後のチャンクを送信（done: true）
                        try await Task.sleep(nanoseconds: 100_000_000) // 少し待ってから完了を送信
                        let finalChunk = ChatResponseChunk(
                            model: model,
                            createdAt: formatter.string(from: created_at),
                            message: ChatMessage(
                                role: "assistant",
                                content: ""
                            ),
                            done: true,
                            totalDuration: 1000000000,  // 1秒
                            loadDuration: 100000000,   // 0.1秒
                            promptEvalCount: 10,
                            promptEvalDuration: 100000000, // 0.1秒
                            evalCount: 5,
                            evalDuration: 500000000,  // 0.5秒
                            doneReason: "stop"
                        )
                        
                        continuation.yield(finalChunk)
                        continuation.finish()
                    } else {
                        // 非ストリーミングモード（stream: false）
                        try await Task.sleep(nanoseconds: 5_000_000_000) // 5秒遅延
                        
                        // 思考モードが有効な場合、thinkingプロパティを持つメッセージを含める
                        let fullResponse = "This is a test!"
                        let thinkingResponse = thinkingOption == .on ? "Testing... Testing... Testing...!" : nil
                        
                        let responseChunk = ChatResponseChunk(
                            model: model,
                            createdAt: formatter.string(from: created_at),
                            message: ChatMessage(
                                role: "assistant",
                                content: fullResponse,
                                thinking: thinkingResponse
                            ),
                            done: true,
                            totalDuration: 1000000,
                            loadDuration: 100000,
                            promptEvalCount: 10,
                            promptEvalDuration: 100000,
                            evalCount: 5,
                            evalDuration: 200000,
                            doneReason: "stop"
                        )
                        
                        continuation.yield(responseChunk)
                        continuation.finish()
                    }
                }
            }
        }
        
        return AsyncThrowingStream { continuation in
            Task { @MainActor in // UIプロパティを安全に更新するためにMainActorで実行することを保証
                guard let apiBaseURL = self.apiBaseURL else {
                    continuation.finish(throwing: URLError(.badURL))
                    return
                }
                let scheme = apiBaseURL.hasPrefix("https://") ? "https" : "http"
                let hostWithoutScheme = apiBaseURL.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
                guard let url = URL(string: "\(scheme)://\(hostWithoutScheme)/api/chat") else {
                    continuation.finish(throwing: URLError(.badURL))
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                do {
                    print("DEBUG: useCustomChatSettings: \(useCustomChatSettings), isTemperatureEnabled: \(isTemperatureEnabled), chatTemperature: \(chatTemperature), isContextWindowEnabled: \(isContextWindowEnabled), contextWindowValue: \(contextWindowValue), isSeedEnabled: \(isSeedEnabled), seed: \(seed), repeatLastN: \(String(describing: repeatLastN)), repeatPenalty: \(String(describing: repeatPenalty)), numPredict: \(String(describing: numPredict)), topK: \(String(describing: topK)), topP: \(String(describing: topP)), minP: \(String(describing: minP)), isSystemPromptEnabled: \(isSystemPromptEnabled), systemPrompt: \(systemPrompt), thinkingOption: \(thinkingOption)")
                    var chatOptions: ChatRequestOptions?
                    if useCustomChatSettings {
                        var options = ChatRequestOptions()
                        if isTemperatureEnabled {
                            options.temperature = chatTemperature
                        }
                        if isContextWindowEnabled {
                            options.numCtx = Int(contextWindowValue) // DoubleをIntにキャスト
                        }
                        if isSeedEnabled {
                            options.seed = seed
                        }
                        
                        // 新しいオプションの設定
                        options.repeatLastN = repeatLastN
                        options.repeatPenalty = repeatPenalty
                        options.numPredict = numPredict
                        options.topK = topK
                        options.topP = topP
                        options.minP = minP
                        
                        chatOptions = options
                        print("DEBUG: Constructed chatOptions: \(String(describing: chatOptions))")
                    }
                    
                    var finalMessages = messages
                    if useCustomChatSettings && isSystemPromptEnabled && !systemPrompt.isEmpty {
                        // システムメッセージが既に存在するか確認
                        if finalMessages.firstIndex(where: { $0.role == "system" }) != nil {
                        } else {
                            // 存在しない場合は新しいものを挿入
                            finalMessages.insert(ChatMessage(role: "system", content: systemPrompt), at: 0)
                        }
                    }
                    
                    let chatRequest: ChatRequest
                    switch thinkingOption {
                    case .none:
                        chatRequest = ChatRequest(model: model, messages: finalMessages, stream: stream, think: nil, keepAlive: keepAlive, options: chatOptions, tools: tools)
                    case .on:
                        chatRequest = ChatRequest(model: model, messages: finalMessages, stream: stream, think: true, keepAlive: keepAlive, options: chatOptions, tools: tools)
                    case .off:
                        chatRequest = ChatRequest(model: model, messages: finalMessages, stream: stream, think: false, keepAlive: keepAlive, options: chatOptions, tools: tools)
                    }
                    
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes] // デバッグ用に整形しつつスラッシュエスケープを無効化
                    request.httpBody = try encoder.encode(chatRequest)
                    print("DEBUG: Final Chat Request Body: \(String(data: request.httpBody!, encoding: .utf8) ?? "Invalid Body")")
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                
                let task = urlSession.dataTask(with: request)
                self.chatContinuations[task] = (continuation: continuation, isStreaming: stream)
                self.chatLineBuffers[task] = "" // このタスクのバッファを初期化
                self.currentChatTask = task // 現在のチャットタスクを保持
                
                task.resume()
            }
        }
    }
    
    /// 現在進行中のチャットストリームをキャンセルします。
    func cancelChatStreaming() {
        currentChatTask?.cancel()
        currentChatTask = nil
        print("Chat streaming cancelled.")
    }
    
    /// 現在進行中の画像生成ストリームをキャンセルします。
    func cancelImageGeneration() {
        currentImageTask?.cancel()
        currentImageTask = nil
        print("Image generation cancelled.")
    }
    
    /// チャット履歴と入力テキストをクリアします。
    func clearChat() {
        chatMessages.removeAll()
        chatInputText = ""
        chatInputImages = []
        updateIsChatStreaming()
        cancelChatStreaming()
    }
    
    /// 画像生成履歴をクリアします。
    func clearImageGeneration() {
        imageMessages.removeAll()
        chatInputText = ""
        imageInputImages = []
        updateIsImageStreaming()
        cancelImageGeneration()
    }
    
    /// Ollamaの /api/generate エンドポイントにリクエストを送信し、画像生成処理を行います。
    func generateImage(model: String, prompt: String, stream: Bool, width: Int, height: Int, steps: Int, seed: Int? = nil, keepAlive: JSONValue? = nil) -> AsyncThrowingStream<ImageGenerationResponseChunk, Error> {
        if isDemoServer() {
            // ... (demo logic)
            return AsyncThrowingStream { continuation in
                Task { @MainActor in
                    let created_at = Date()
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let createdAtString = formatter.string(from: created_at)
                    
                    if stream {
                        // ステップごとの進捗をシミュレート
                        for i in 1...steps {
                            // 各ステップの間隔をシミュレート
                            try await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
                            
                            let chunk = ImageGenerationResponseChunk(
                                model: model,
                                createdAt: createdAtString,
                                response: nil,
                                done: false,
                                image: nil, // 中間ステップでは画像を送らない
                                completed: i,
                                total: steps,
                                totalDuration: nil,
                                loadDuration: nil,
                                promptEvalCount: nil,
                                promptEvalDuration: nil,
                                evalCount: nil,
                                evalDuration: nil
                            )
                            continuation.yield(chunk)
                        }
                        
                        // 完了：センタークロップした画像を送る
                        let finalImageString = processDemoImage(targetWidth: CGFloat(width), targetHeight: CGFloat(height))
                        let totalSimulatedDuration = Int(Double(steps) * 200_000_000) // 1ステップ0.2秒(200ms)
                        
                        // 完了時の時刻を取得
                        let completionDate = Date()
                        let finalCreatedAtString = formatter.string(from: completionDate)
                        
                        let finalChunk = ImageGenerationResponseChunk(
                            model: model,
                            createdAt: finalCreatedAtString,
                            response: "",
                            done: true,
                            image: finalImageString,
                            completed: steps,
                            total: steps,
                            totalDuration: totalSimulatedDuration,
                            loadDuration: nil,
                            promptEvalCount: nil,
                            promptEvalDuration: nil,
                            evalCount: nil,
                            evalDuration: nil
                        )
                        continuation.yield(finalChunk)
                        continuation.finish()
                    } else {
                        // 非ストリーミング：少し待ってから完成品を返す
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                        let finalImageString = processDemoImage(targetWidth: CGFloat(width), targetHeight: CGFloat(height))
                        let totalSimulatedDuration = Int(Double(steps) * 200_000_000)
                        
                        // 完了時の時刻を取得
                        let completionDate = Date()
                        let finalCreatedAtString = formatter.string(from: completionDate)
                        
                        let finalChunk = ImageGenerationResponseChunk(
                            model: model,
                            createdAt: finalCreatedAtString,
                            response: "",
                            done: true,
                            image: finalImageString,
                            completed: steps,
                            total: steps,
                            totalDuration: totalSimulatedDuration,
                            loadDuration: nil,
                            promptEvalCount: nil,
                            promptEvalDuration: nil,
                            evalCount: nil,
                            evalDuration: nil
                        )
                        continuation.yield(finalChunk)
                        continuation.finish()
                    }
                }
            }
        }
        
        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                guard let apiBaseURL = self.apiBaseURL else {
                    continuation.finish(throwing: URLError(.badURL))
                    return
                }
                let scheme = apiBaseURL.hasPrefix("https://") ? "https" : "http"
                let hostWithoutScheme = apiBaseURL.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
                guard let url = URL(string: "\(scheme)://\(hostWithoutScheme)/api/generate") else {
                    continuation.finish(throwing: URLError(.badURL))
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                // オプション設定
                var options: ChatRequestOptions? = nil
                if let seedValue = seed {
                    options = ChatRequestOptions(seed: seedValue)
                }
                
                let generationRequest = ImageGenerationRequest(
                    model: model,
                    prompt: prompt,
                    stream: stream,
                    keepAlive: keepAlive,
                    width: width,
                    height: height,
                    steps: steps,
                    options: options
                )
                
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .withoutEscapingSlashes
                    request.httpBody = try encoder.encode(generationRequest)
                    print("DEBUG: Image Generation Request Body: \(String(data: request.httpBody!, encoding: .utf8) ?? "Invalid Body")")
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                
                let task = urlSession.dataTask(with: request)
                self.imageContinuations[task] = (continuation: continuation, isStreaming: stream)
                self.imageLineBuffers[task] = ""
                self.currentImageTask = task
                
                task.resume()
            }
        }
    }
    
    /// デモモード用の画像を処理（切り抜き）してBase64文字列を返します
    private func processDemoImage(targetWidth: CGFloat, targetHeight: CGFloat) -> String? {
        let assetName = "ImageGenerationTestImage"
        
        #if os(macOS)
        guard let image = NSImage(named: assetName),
              let tiffData = image.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            print("Demo mode: Failed to load asset '\(assetName)'")
            return nil
        }
        #else
        guard let image = UIImage(named: assetName),
              let ciImage = CIImage(image: image) else {
            print("Demo mode: Failed to load asset '\(assetName)'")
            return nil
        }
        #endif
        
        // 1. センタークロップ（指定されたアスペクト比で切り抜き）
        let sourceExtent = ciImage.extent
        let targetAspectRatio = targetWidth / targetHeight
        let sourceAspectRatio = sourceExtent.width / sourceExtent.height
        
        var cropRect = sourceExtent
        if targetAspectRatio > sourceAspectRatio {
            // ターゲットの方が横長 -> 元画像の上下を削る
            let newHeight = sourceExtent.width / targetAspectRatio
            cropRect = CGRect(x: 0, y: (sourceExtent.height - newHeight) / 2, width: sourceExtent.width, height: newHeight)
        } else {
            // ターゲットの方が縦長 -> 元画像の左右を削る
            let newWidth = sourceExtent.height * targetAspectRatio
            cropRect = CGRect(x: (sourceExtent.width - newWidth) / 2, y: 0, width: newWidth, height: sourceExtent.height)
        }
        
        var croppedImage = ciImage.cropped(to: cropRect)
        // クロップ後の座標を(0,0)基準にリセット
        croppedImage = croppedImage.transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))
        
        // 2. 画像の書き出し（PNG形式）
        let context = CIContext()
        guard let cgImage = context.createCGImage(croppedImage, from: croppedImage.extent) else { return nil }
        
        #if os(macOS)
        let resultImage = NSImage(cgImage: cgImage, size: croppedImage.extent.size)
        guard let data = resultImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return pngData.base64EncodedString()
        #else
        let resultImage = UIImage(cgImage: cgImage)
        guard let pngData = resultImage.pngData() else { return nil }
        return pngData.base64EncodedString()
        #endif
    }
    
    
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        Task { @MainActor [weak self, completionHandler] in
            guard let self = self else {
                completionHandler(.cancel)
                return
            }
            
            // タスクの種類を確認（プルタスクかどうか）
            let isPullTask = (dataTask == self.pullTask)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                // プルタスクの場合のみ、ここでエラー終了させる
                if isPullTask {
                    if let url = dataTask.originalRequest?.url { print("/api/pull HTTP error: \(httpResponse.statusCode) on \(url)") }
                    let base = String(format: NSLocalizedString("Model pull error: HTTP Status Code %d", comment: "モデルプルエラー: HTTPステータスコード。"), httpResponse.statusCode)
                    self.output = base
                    if httpResponse.statusCode == 400 {
                        self.pullHttpErrorMessage = NSLocalizedString("Model pull failed.\nPlease make sure the model name is correct.", comment: "400 Bad Request: likely wrong model name")
                    } else {
                        self.pullHttpErrorMessage = NSLocalizedString("Model pull failed.\nUnknown error occurred.", comment: "Non-400 error fallback message")
                    }
                    self.pullHttpErrorTriggered = true
                    self.pullHasError = true
                    self.pullStatus = NSLocalizedString("Failed", comment: "失敗")
                    self.isPullingErrorHold = true
                    self.isPulling = false
                    completionHandler(.cancel)
                    return
                }
                // チャットや画像生成の場合は、後続の dataReceive でエラー詳細（JSON）を取得したいため、継続を許可する
            }
            self.pullLineBuffer = ""
            completionHandler(.allow)
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            if dataTask == self.pullTask {
                // プルタスクの処理
                if let newString = String(data: data, encoding: .utf8) {
                    self.pullLineBuffer.append(newString)
                } else {
                    print("Error: Could not decode received data as UTF-8 string.")
                    return
                }
                
                var lines = self.pullLineBuffer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                
                if !self.pullLineBuffer.hasSuffix("\n") && !lines.isEmpty {
                    self.pullLineBuffer = lines.removeLast()
                } else {
                    self.pullLineBuffer = ""
                }
                
                for line in lines {
                    guard !line.isEmpty else { continue }
                    guard let jsonData = line.data(using: .utf8) else {
                        print("Error: Could not convert line to Data: \(line)")
                        continue
                    }
                    
                    do {
                        let response = try JSONDecoder().decode(OllamaPullResponse.self, from: jsonData)
                        
                        // 速度計算のための処理はリアルタイムで行う
                        if let total = response.total {
                            self.pendingPullTotal = total
                        }
                        if let completed = response.completed {
                            self.pendingPullCompleted = completed
                        }
                        
                        if self.pendingPullTotal > 0 {
                            var calculatedProgress = Double(self.pendingPullCompleted) / Double(self.pendingPullTotal)
                            calculatedProgress = min(max(0.0, calculatedProgress), 1.0)
                            self.pendingPullProgress = calculatedProgress
                        } else {
                            self.pendingPullProgress = 0.0
                        }
                        
                        let now = Date()
                        if let lastTime = self.lastSpeedSampleTime {
                            let dt = now.timeIntervalSince(lastTime)
                            if dt > 0.5 { // 0.5秒以上の間隔でサンプリング
                                let dBytes = Double(self.pendingPullCompleted - self.lastSpeedSampleCompleted)
                                if dBytes >= 0 {
                                    let speed = dBytes / dt
                                    self.pullSpeedBytesPerSec = speed
                                    if self.pendingPullTotal > 0 {
                                        let remainingBytes = Double(self.pendingPullTotal - self.pendingPullCompleted)
                                        if speed > 0 {
                                            self.pullETARemaining = remainingBytes / speed
                                        }
                                    }
                                }
                                self.lastSpeedSampleTime = now
                                self.lastSpeedSampleCompleted = self.pendingPullCompleted
                            }
                        } else {
                            self.lastSpeedSampleTime = now
                            self.lastSpeedSampleCompleted = self.pendingPullCompleted
                        }
                        
                        // プルステータスおよび進捗の更新は0.5秒ごとに制限
                        if !self.pullHasError {
                            self.pendingPullStatus = response.status
                        }
                        
                        // UI更新タイマーを設定
                        if self.pullStatusUpdateTimer == nil {
                            self.pullStatusUpdateTimer = Timer.scheduledTimer(withTimeInterval: self.pullStatusUpdateInterval, repeats: true) { _ in
                                Task { @MainActor in
                                    self.updatePullStatusIfNeeded()
                                }
                            }
                        }
                        
                        print("Pull status: \(self.pullStatus), Completed: \(self.pendingPullCompleted), Total: \(self.pendingPullTotal), Progress: \(String(format: "%.2f", self.pendingPullProgress))")
                    } catch {
                        if let debugString = String(data: jsonData, encoding: .utf8) {
                            print("Pull stream JSON decode error: \(error.localizedDescription) - Line: \(debugString)")
                            if debugString.contains("\"error\":") || debugString.lowercased().contains("error") {
                                self.output = debugString
                                self.pullHasError = true
                                self.pullStatus = NSLocalizedString("Error", comment: "エラー")
                                self.isPullingErrorHold = true
                            }
                        } else {
                            print("Pull stream JSON decode error: \(error.localizedDescription) - Line data unreadable.")
                        }
                    }
                }
            } else if let (continuation, isStreaming) = self.chatContinuations[dataTask] {
                if let httpResponse = dataTask.response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    // HTTPエラーがある場合はJSONデコードを試みるが、失敗してもエラーを投げて終了させる
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMessage = errorJson["error"] as? String {
                        let error = NSError(domain: "OllamaAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
                        continuation.finish(throwing: error)
                    } else {
                        let error = NSError(domain: "OllamaAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned error \(httpResponse.statusCode)"])
                        continuation.finish(throwing: error)
                    }
                    return
                }
                
                if isStreaming {
                    // ストリーミングチャットの処理
                    if let newString = String(data: data, encoding: .utf8) {
                        self.chatLineBuffers[dataTask, default: ""].append(newString)
                    } else {
                        print("Error: Could not decode received data as UTF-8 string.")
                        return
                    }
                    
                    var lines = self.chatLineBuffers[dataTask, default: ""].split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                    
                    if !self.chatLineBuffers[dataTask, default: ""].hasSuffix("\n") && !lines.isEmpty {
                        self.chatLineBuffers[dataTask] = lines.removeLast()
                    } else {
                        self.chatLineBuffers[dataTask] = ""
                    }
                    
                    for line in lines {
                        guard !line.isEmpty else { continue }
                        guard let jsonData = line.data(using: .utf8) else {
                            print("Error: Could not convert line to Data: \(line)")
                            continue
                        }
                        
                        do {
                            let chunk = try JSONDecoder().decode(ChatResponseChunk.self, from: jsonData)
                            continuation.yield(chunk)
                        } catch {
                            print("Chat response JSON decode error: \(error.localizedDescription) - Line: \(line)")
                        }
                    }
                } else {
                    // 非ストリーミングチャットの処理
                    do {
                        let chunk = try JSONDecoder().decode(ChatResponseChunk.self, from: data)
                        continuation.yield(chunk)
                        continuation.finish() // 非ストリーミングなので、一度だけyieldして終了
                    } catch {
                        print("Non-streaming chat response JSON decode error: \(error.localizedDescription) - Data: \(String(data: data, encoding: .utf8) ?? "Unreadable Data")")
                        continuation.finish(throwing: error)
                    }
                }
            } else if let (continuation, isStreaming) = self.imageContinuations[dataTask] {
                if let httpResponse = dataTask.response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    // HTTPエラーがある場合はJSONデコードを試みるが、失敗してもエラーを投げて終了させる
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMessage = errorJson["error"] as? String {
                        let error = NSError(domain: "OllamaAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
                        continuation.finish(throwing: error)
                    } else {
                        let error = NSError(domain: "OllamaAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned error \(httpResponse.statusCode)"])
                        continuation.finish(throwing: error)
                    }
                    return
                }
                
                if isStreaming {
                    // ストリーミング画像生成の処理
                    if let newString = String(data: data, encoding: .utf8) {
                        self.imageLineBuffers[dataTask, default: ""].append(newString)
                    } else {
                        print("Error: Could not decode received data as UTF-8 string.")
                        return
                    }
                    
                    var lines = self.imageLineBuffers[dataTask, default: ""].split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                    
                    if !self.imageLineBuffers[dataTask, default: ""].hasSuffix("\n") && !lines.isEmpty {
                        self.imageLineBuffers[dataTask] = lines.removeLast()
                    } else {
                        self.imageLineBuffers[dataTask] = ""
                    }
                    
                    for line in lines {
                        guard !line.isEmpty else { continue }
                        guard let jsonData = line.data(using: .utf8) else {
                            print("Error: Could not convert line to Data: \(line)")
                            continue
                        }
                        
                        do {
                            let chunk = try JSONDecoder().decode(ImageGenerationResponseChunk.self, from: jsonData)
                            continuation.yield(chunk)
                        } catch {
                            print("Image generation response JSON decode error: \(error.localizedDescription) - Line: \(line)")
                            // デコード失敗時に生のデータを表示（エラーメッセージ確認用）
                            if let errorJson = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                               let errorMessage = errorJson["error"] as? String {
                                print("Ollama API Error: \(errorMessage)")
                            }
                        }
                    }
                } else {
                    // 非ストリーミング画像生成の処理
                    do {
                        let chunk = try JSONDecoder().decode(ImageGenerationResponseChunk.self, from: data)
                        continuation.yield(chunk)
                        continuation.finish()
                    } catch {
                        print("Non-streaming image generation response JSON decode error: \(error.localizedDescription) - Data: \(String(data: data, encoding: .utf8) ?? "Unreadable Data")")
                        // エラーメッセージの抽出
                        if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let errorMessage = errorJson["error"] as? String {
                            print("Ollama API Error: \(errorMessage)")
                        }
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }
    
    /// プルステータスを実際に更新するメソッド（0.5秒ごとに呼び出される）
    private func updatePullStatusIfNeeded() {
        let now = Date()
        if now.timeIntervalSince(self.lastPullStatusUpdate) >= self.pullStatusUpdateInterval {
            if let pendingStatus = self.pendingPullStatus {
                self.pullStatus = pendingStatus
                self.pendingPullStatus = nil
            }
            self.pullTotal = self.pendingPullTotal
            self.pullCompleted = self.pendingPullCompleted
            self.pullProgress = self.pendingPullProgress
            self.lastPullStatusUpdate = now
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            if task == self.pullTask {
                self.pullTask = nil
                self.pullLineBuffer = ""
                
                // プルタスク完了時にタイマーを停止
                self.pullStatusUpdateTimer?.invalidate()
                self.pullStatusUpdateTimer = nil
                
                if let error = error {
                    if self.pullHasError || self.pullStatus == NSLocalizedString("Error", comment: "エラー") || self.pullStatus == NSLocalizedString("Failed", comment: "失敗") {
                        print("Retaining: Overlay maintained due to pull error. error=\(error.localizedDescription)")
                        self.isPullingErrorHold = true
                        return
                    }
                    self.output = NSLocalizedString("Model pull failed: ", comment: "Ollamaサーバー上でモデルダウンロード失敗メッセージのプレフィックス。") + error.localizedDescription
                    self.pullStatus = NSLocalizedString("Failed", comment: "プルステータス: 失敗。")
                    self.isPullingErrorHold = true
                    print("Model pull failed with error: \(error.localizedDescription)")
                    self.isPulling = false
                } else {
                    if self.pullHasError {
                        print("Completed: However, not marked as Completed due to an error detected midway.")
                        self.isPulling = false
                        return
                    }
                    self.output = NSLocalizedString("Model pull completed: ", comment: "Ollamaサーバー上でモデルのダウンロード完了メッセージのプレフィックス。") + self.pullStatus
                    self.pullProgress = 1.0
                    self.pullStatus = NSLocalizedString("Completed", comment: "Ollamaサーバー上でモデルのダウンロードに成功したときの完了メッセージ。")
                    print("Model pull completed.")
                    await self.fetchOllamaModelsFromAPI()
                    self.isPulling = false
                }
            } else if let (continuation, _) = self.chatContinuations[task] {
                // チャットタスクの完了を処理
                if let error = error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            } else if let (continuation, _) = self.imageContinuations[task] {
                // 画像生成タスクの完了を処理
                if let error = error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }
            
            // 完了したタスクのリソースをクリーンアップ
            self.chatContinuations.removeValue(forKey: task)
            self.chatLineBuffers.removeValue(forKey: task)
            self.imageContinuations.removeValue(forKey: task)
            self.imageLineBuffers.removeValue(forKey: task)
            
            if task == self.currentChatTask {
                self.currentChatTask = nil
            }
            if task == self.currentImageTask {
                self.currentImageTask = nil
            }
        }
    }
}

// MARK: - Ollama API レスポンスモデル

struct OllamaAPIModelsResponse: Decodable {
    let models: [OllamaModel]
}

/// /api/show エンドポイントからのレスポンス
struct OllamaShowResponse: Decodable {
    let license: String?
    let modelfile: String?
    let parameters: String?
    let template: String?
    let details: OllamaModelDetails?
    let model_info: [String: JSONValue]?
    let capabilities: [String]?
    
}

struct OllamaPullResponse: Decodable {
    let status: String
    let digest: String?
    let total: Int64?
    let completed: Int64?
}

struct OllamaVersionResponse: Decodable {
    let version: String
}

struct OllamaPSResponse: Decodable {
    let models: [OllamaRunningModel]
}

struct OllamaRunningModel: Decodable {
    let name: String
    let expires_at: Date?
    let size_vram: Int64?
    
    var formattedVRAMSize: String? { // VRAMサイズをフォーマット
        guard let size = size_vram else { return nil }
        let byteCountFormatter = ByteCountFormatter()
        byteCountFormatter.countStyle = .file
        return byteCountFormatter.string(fromByteCount: size)
    }
    
    // イニシャライザを追加
    init(name: String, expires_at: Date?, size_vram: Int64?) {
        self.name = name
        self.expires_at = expires_at
        self.size_vram = size_vram
    }
    
    // ISO 8601日付文字列を処理するためのカスタムデコーディング
    enum CodingKeys: String, CodingKey {
        case name
        case expires_at
        case size_vram
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        
        if let expiresAtString = try? container.decode(String.self, forKey: .expires_at) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            expires_at = formatter.date(from: expiresAtString)
        } else {
            expires_at = nil
        }
        size_vram = try? container.decode(Int64.self, forKey: .size_vram)
    }
}

