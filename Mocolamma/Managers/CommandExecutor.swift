import Foundation
import SwiftUI // @Published を使うため
import Combine // CombineフレームワークをインポートしてPublisherを購読可能にする

@preconcurrency @MainActor // @preconcurrency を追加して、URLSessionDelegateのデリゲートメソッドに関する警告を抑制します
class CommandExecutor: NSObject, ObservableObject, URLSessionDelegate, URLSessionDataDelegate {
    @Published var output: String = "" // 公開用の生のコマンド出力（stdout + stderr + 終了メッセージ）
    @Published var isRunning: Bool = false
    @Published var pullHttpErrorTriggered: Bool = false
    @Published var pullHttpErrorMessage: String = ""
    @Published var models: [OllamaModel] = [] // 解析されたモデルリスト
    @Published var apiConnectionError: Bool = false // API接続エラーの状態を追加
    @Published var specificConnectionErrorMessage: String? // 特定の接続エラーメッセージを追加
    @Published var chatMessages: [ChatMessage] = [] // チャットメッセージ
    @Published var chatInputText: String = "" // チャット入力テキスト
    
    // モデルプル時の進捗状況
    @Published var isPulling: Bool = false
    @Published var isPullingErrorHold: Bool = false
    @Published var pullHasError: Bool = false
    @Published var pullStatus: String = "Preparing..." // プルステータス: 準備中。
    @Published var pullProgress: Double = 0.0 // 0.0 から 1.0
    @Published var pullTotal: Int64 = 0 // 合計バイト数
    @Published var pullCompleted: Int64 = 0 // 完了したバイト数
    @Published var pullSpeedBytesPerSec: Double = 0.0 // 現在のダウンロード速度(B/s)
    @Published var pullETARemaining: TimeInterval = 0 // 残り推定時間(秒)
    @Published var lastPulledModelName: String = "" // 最後にプルリクエストを送ったモデル名
    private var urlSession: URLSession!
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
    private let pullStatusUpdateInterval: TimeInterval = 0.5 // プルステータスの更新間隔（秒）
    private var chatContinuations: [URLSessionTask: (continuation: AsyncThrowingStream<ChatResponseChunk, Error>.Continuation, isStreaming: Bool)] = [:]
    private var chatLineBuffers: [URLSessionTask: String] = [:]
    private var currentChatTask: URLSessionDataTask? // 現在のチャットタスクを保持
    
    // Ollama APIのベースURL
    // ServerManagerから現在のサーバーホストを受け取るように変更
    @Published var apiBaseURL: String?
    
    private var cancellables = Set<AnyCancellable>() // ServerManagerの変更を監視するためのSet
    
    // MARK: - モデル情報キャッシュ
    private var modelInfoCache: [String: OllamaShowResponse] = [:]
    
    /// CommandExecutorのイニシャライザ。ServerManagerのインスタンスを受け取り、APIベースURLを監視します。
    /// - Parameter serverManager: サーバーリストと選択状態を管理するServerManagerのインスタンス。
    init(serverManager: ServerManager) {
        // 初期化時にServerManagerから現在のホストURLを設定
        self.apiBaseURL = serverManager.currentServerHost
        super.init()
        // デリゲートキューをnilに設定し、デリゲートメソッドがバックグラウンドスレッドで実行されるようにします
        // デリゲートメソッド内で @MainActor への切り替えをTask { @MainActor in ... } で明示的に行います
        let configuration = URLSessionConfiguration.default
        let opt = APITimeoutManager.shared.currentOption
        configuration.timeoutIntervalForRequest = opt.requestTimeoutUntilFirstByte
        configuration.timeoutIntervalForResource = opt.overallResourceTimeout
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        
        // ServerManagerのcurrentServerHostの変更を監視し、apiBaseURLを更新
        serverManager.$servers
            .map { servers in
                // serversリストが変更された場合、selectedServerIDに基づき新しいcurrentServerHostを計算
                // selectedServerIDがない場合や、対応するサーバーがserversにない場合を考慮
                if let selectedID = serverManager.selectedServerID,
                   let selectedServer = servers.first(where: { $0.id == selectedID }) {
                    return selectedServer.host
                }
                // フォールバックを削除し、nilを返す
                return nil
            }
            .assign(to: \.apiBaseURL, on: self)
            .store(in: &cancellables)
        
        serverManager.$selectedServerID
            .compactMap { selectedID in
                // selectedIDが変更された場合、対応するサーバーのホストを返す
                serverManager.servers.first(where: { $0.id == selectedID })?.host
            }
            .assign(to: \.apiBaseURL, on: self)
            .store(in: &cancellables)
        
        // apiBaseURLの変更を監視し、モデルリストを再取得
        $apiBaseURL
            .sink { [weak self] _ in
                Task {
                    await self?.fetchOllamaModelsFromAPI()
                }
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
    
    /// Ollama APIからモデルリストを取得します (async/await版)
    func fetchOllamaModelsFromAPI() async {
        guard let apiBaseURL = self.apiBaseURL else {
            // apiBaseURLがnilの場合、何もしない
            print("Ollama APIベースURLが設定されていません。モデルリストの取得をスキップします。")
            self.output = NSLocalizedString("Error: No Ollama server selected.", comment: "Ollamaサーバーが選択されていません。")
            self.apiConnectionError = true
            return
        }
        print("Ollama APIから \(apiBaseURL) のモデルリストを取得中...")
        // UI更新はメインアクターで行います
        self.output = String(format: NSLocalizedString("Fetching models from API (%@)...", comment: "APIからモデルを取得中のステータスメッセージ。"), apiBaseURL)
        try? await Task.sleep(nanoseconds: 100_000_000)
        self.isRunning = true
        self.apiConnectionError = false // 新しいフェッチの前にエラー状態をリセット
        
        // defer を使って関数終了時に必ず isRunning を false に設定します
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
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.output = NSLocalizedString("API Error: Unknown response type.", comment: "不明なAPIレスポンスタイプのエラーメッセージ。")
                print("API エラー: 不明なレスポンスタイプです。")
                self.models = [] // エラー時もモデルリストをクリア
                self.apiConnectionError = true // API接続エラーを設定
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                let statusMessage = String(format: NSLocalizedString("API Error: HTTP Status Code %d", comment: "HTTPステータスコードのエラーメッセージ。"), httpResponse.statusCode)
                self.output = statusMessage
                print("API エラー: HTTPステータスコード \(httpResponse.statusCode)")
                if let errorString = String(data: data, encoding: .utf8) {
                    print("API エラーレスポンス: \(errorString)")
                }
                self.models = [] // エラー時もモデルリストをクリア
                self.apiConnectionError = true // API接続エラーを設定
                return
            }
            
            print("デコードを試行中。データサイズ: \(data.count) バイト。最初の10バイト: \(data.prefix(10).map { String(format: "%02x", $0) }.joined())...")
            
            let apiResponse = try JSONDecoder().decode(OllamaAPIModelsResponse.self, from: data)
            self.models = apiResponse.models.enumerated().map { (index, model) in
                var mutableModel = model
                mutableModel.originalIndex = index
                return mutableModel
            }
            let successMessage = String(format: NSLocalizedString("Successfully fetched models. Total: %d", comment: "モデル取得成功のメッセージ。"), self.models.count)
            self.output = successMessage
            print("モデル取得に成功しました。合計: \(self.models.count)")
            self.apiConnectionError = false // 成功時はエラーなし
            
        } catch let decodingError as DecodingError {
            self.output = NSLocalizedString("API Decode Error: ", comment: "APIデコードエラーのプレフィックス。") + decodingError.localizedDescription
            print("APIデコードエラー: \(decodingError.localizedDescription)")
            self.models = [] // デコードエラー時もモデルリストをクリア
            self.apiConnectionError = true // API接続エラーを設定
            
            switch decodingError {
            case .keyNotFound(let key, let context):
                print("DecodingError.keyNotFound: キー '\(key.stringValue)' が見つかりません。\(context.debugDescription)")
                print("コーディングパス: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .typeMismatch(let type, let context):
                print("DecodingError.typeMismatch: タイプ '\(type)' が一致しません。\(context.debugDescription)")
                print("コーディングパス: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .valueNotFound(let type, let context):
                print("DecodingError.valueNotFound: タイプ '\(type)' の値が見つかりません。\(context.debugDescription)")
                print("コーディングパス: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .dataCorrupted(let context):
                print("DecodingError.dataCorrupted: データが破損しています。\(context.debugDescription)")
                print("コーディングパス: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            @unknown default:
                print("不明なDecodingError: \(decodingError.localizedDescription)")
            }
            
        } catch {
            self.output = NSLocalizedString("API Request Error: ", comment: "APIリクエストエラーのプレフィックス。") + error.localizedDescription
            print("APIリクエストエラー（その他）: \(error.localizedDescription)")
            self.models = [] // その他のエラー時もモデルリストをクリア
            self.apiConnectionError = true // API接続エラーを設定
        }
    }
    
    /// モデルをダウンロードします (デリゲートを使用するため async化はしませんが、UI更新は @MainActor にディスパッチします)
    func pullModel(modelName: String) {
        guard let apiBaseURL = self.apiBaseURL else {
            print("Ollama APIベースURLが設定されていません。モデルのプルをスキップします。")
            self.output = NSLocalizedString("Error: No Ollama server selected.", comment: "Ollamaサーバーが選択されていません。")
            self.isPulling = false
            return
        }
        print("モデル \(modelName) を \(apiBaseURL) からプルを試行中")
        // UI更新はメインアクターで行います
        self.output = String(format: NSLocalizedString("Downloading model '%@' from %@...", comment: "モデルダウンロード中のステータスメッセージ。"), modelName, apiBaseURL)
        self.isPulling = true
        self.isPullingErrorHold = false
        self.pullHasError = false
        self.pullStatus = NSLocalizedString("Preparing...", comment: "プルステータス: 準備中。")
        self.pullProgress = 0.0
        self.pullTotal = 0
        self.pullCompleted = 0
        self.pullSpeedBytesPerSec = 0.0
        self.pullETARemaining = 0
        self.lastSpeedSampleTime = nil
        self.lastSpeedSampleCompleted = 0
        self.lastPulledModelName = modelName // 最後にプルリクエストを送ったモデル名を更新
        
        let scheme = apiBaseURL.hasPrefix("https://") ? "https" : "http"
        let hostWithoutScheme = apiBaseURL.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        guard let url = URL(string: "\(scheme)://\(hostWithoutScheme)/api/pull") else {
            self.output = NSLocalizedString("Error: Invalid API URL for pull.", comment: "プル用API URLが無効な場合のエラーメッセージ。")
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
            self.output = NSLocalizedString("Error: Failed to serialize pull request body: ", comment: "プルリクエストボディのシリアライズ失敗のエラーメッセージ。") + error.localizedDescription
            self.isPulling = false
            return
        }
        
        pullTask?.cancel()
        pullTask = urlSession.dataTask(with: request)
        pullTask?.resume()
    }
    
    /// モデルを削除します
    func deleteModel(modelName: String) async {
        guard let apiBaseURL = self.apiBaseURL else {
            print("Ollama APIベースURLが設定されていません。モデルの削除をスキップします。")
            self.output = NSLocalizedString("Error: No Ollama server selected.", comment: "Ollamaサーバーが選択されていません。")
            return
        }
        print("モデル \(modelName) を \(apiBaseURL) から削除を試行中")
        // UI更新はメインアクターで行います
        self.output = String(format: NSLocalizedString("Deleting model '%@' from %@...", comment: "モデル削除中のステータスメッセージ。"), modelName, apiBaseURL)
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
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.output = NSLocalizedString("Delete Error: Unknown response type.", comment: "削除エラー: 不明なレスポンスタイプのエラーメッセージ。")
                print("削除エラー: 不明なレスポンスタイプです。")
                return
            }
            
            if httpResponse.statusCode == 200 {
                self.output = String(format: NSLocalizedString("Successfully deleted model '%@' from %@.", comment: "モデル削除成功のメッセージ。"), modelName, apiBaseURL)
                print("モデル '\(modelName)' を \(apiBaseURL) から正常に削除しました。")
                await self.fetchOllamaModelsFromAPI() // メインアクターで実行されるasync関数なので直接呼び出し可能です
                
            } else if httpResponse.statusCode == 404 {
                self.output = String(format: NSLocalizedString("Delete Error: Model '%@' not found (404 Not Found) on %@.", comment: "削除エラー: モデルが見つからない場合のエラーメッセージ。"), modelName, apiBaseURL)
                print("削除エラー: モデル '\(modelName)' が \(apiBaseURL) で見つかりません（404）。")
            } else {
                let errorString = String(data: data, encoding: .utf8) ?? NSLocalizedString("No data available", comment: "データなし。")
                let errorMessage = String(format: NSLocalizedString("Delete Error: HTTP Status Code %d - %@ on %@", comment: "削除エラー: HTTPステータスコードのエラーメッセージ。"), httpResponse.statusCode, errorString, apiBaseURL)
                self.output = errorMessage
                print("削除エラー: HTTPステータスコード \(httpResponse.statusCode) - \(errorString) on \(apiBaseURL)")
            }
        } catch {
            self.output = NSLocalizedString("Model deletion failed: ", comment: "モデル削除失敗のプレフィックス。") + error.localizedDescription
            print("モデル削除に失敗しました: \(error.localizedDescription)")
        }
    }
    
    /// モデルの詳細情報を取得します (async/await版)
    func fetchModelInfo(modelName: String) async -> OllamaShowResponse? {
        // キャッシュに存在すればそれを返す
        if let cachedInfo = modelInfoCache[modelName] {
            print("モデル \(modelName) の詳細情報をキャッシュから取得しました。")
            return cachedInfo
        }
        
        print("モデル \(modelName) の詳細情報を \(String(describing: apiBaseURL)) から取得中...")
        
        guard let apiBaseURL = self.apiBaseURL else {
            print("Ollama APIベースURLが設定されていません。モデルの詳細情報の取得をスキップします。")
            return nil
        }
        print("モデル \(modelName) の詳細情報を \(String(describing: apiBaseURL)) から取得中...")
        
        let scheme = apiBaseURL.hasPrefix("https://") ? "https" : "http"
        let hostWithoutScheme = apiBaseURL.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        guard let url = URL(string: "\(scheme)://\(hostWithoutScheme)/api/show") else {
            print("エラー: /api/show のURLが無効です。")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["model": modelName]
        
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            print("エラー: リクエストボディのエンコードに失敗しました: \(error)")
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("APIエラー: /api/show - HTTPステータスコード \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            
            let apiResponse = try JSONDecoder().decode(OllamaShowResponse.self, from: data)
            print("モデル \(modelName) の詳細情報を正常に取得しました。")
            // 取得した情報をキャッシュに保存
            modelInfoCache[modelName] = apiResponse
            
            // 変更点: selectedModelContextLength の更新ロジックを削除
            
            return apiResponse
            
        } catch {
            print("APIリクエストエラー: /api/show - \(error.localizedDescription)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("DecodingError.keyNotFound: キー '\(key.stringValue)' が見つかりません。\(context.debugDescription)")
                    print("コーディングパス: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .typeMismatch(let type, let context):
                    print("DecodingError.typeMismatch: タイプ '\(type)' が一致しません。\(context.debugDescription)")
                    print("コーディングパス: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .valueNotFound(let type, let context):
                    print("DecodingError.valueNotFound: タイプ '\(type)' の値が見つかりません。\(context.debugDescription)")
                    print("コーディングパス: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .dataCorrupted(let context):
                    print("DecodingError.dataCorrupted: データが破損しています。\(context.debugDescription)")
                    print("コーディングパス: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                @unknown default:
                    print("不明なDecodingError: \(decodingError.localizedDescription)")
                }
            }
            return nil
        }
    }
    
        /// 指定されたホストにOllama APIが接続可能かを確認します。
        /// - Parameter host: 接続を試みるホストURL文字列 (例: "localhost:11434")。
        /// - Returns: 接続状態を示す `ServerConnectionStatus`。
        func checkAPIConnectivity(host: String) async -> ServerConnectionStatus {
            let scheme = host.hasPrefix("https://") ? "https" : "http"
            let hostWithoutScheme = host.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            guard let url = URL(string: "\(scheme)://\(hostWithoutScheme)/api/tags") else {
                print("接続確認エラー: ホスト \(host) のURLが無効です")
                return .unknownHost
            }
    
            var request = URLRequest(url: url)
            request.httpMethod = "GET" // GETリクエストに変更してエラー情報を取得
    
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        print("接続確認: \(host) への接続に成功しました")
                        return .connected
                    } else {
                        print("接続確認: \(host) への接続に失敗しました - HTTPステータスコード: \(httpResponse.statusCode)")
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
                print("\(host) への接続確認エラー: \(error.localizedDescription)")
                // TLSエラーのチェック
                if scheme == "https" && (
                    error.code == .secureConnectionFailed ||
                    error.code == .serverCertificateUntrusted ||
                    error.code == .cannotConnectToHost || // 接続できない場合もTLS関連の可能性あり
                    error.code == .networkConnectionLost // 接続が失われた場合もTLS関連の可能性あり
                ) {
                    self.specificConnectionErrorMessage = NSLocalizedString("Could not connect to API.\nTLS error occurred, could not establish a secure connection.", comment: "TLS connection error message.")
                } else {
                    self.specificConnectionErrorMessage = nil // 他のエラーの場合はクリア
                }
                return .unknownHost
            } catch {
                print("\(host) への接続確認エラー: \(error.localizedDescription)")
                self.specificConnectionErrorMessage = nil // URLError以外のエラーの場合はクリア
                return .unknownHost
            }
        }    
    /// Ollamaのバージョンを取得します。
    /// - Parameter host: OllamaホストのURL。
    /// - Returns: Ollamaのバージョン文字列。
    func fetchOllamaVersion(host: String) async throws -> String {
        let scheme = host.hasPrefix("https://") ? "https" : "http"
        let hostWithoutScheme = host.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        guard let url = URL(string: "\(scheme)://\(hostWithoutScheme)/api/version") else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(OllamaVersionResponse.self, from: data)
        return response.version
    }
    
    /// モデル情報キャッシュをクリアします。
    func clearModelInfoCache() {
        modelInfoCache.removeAll()
        print("モデル情報キャッシュをクリアしました。")
    }
    
    /// 現在メモリにロードされているモデル数を取得します。
    func fetchRunningModelsCount(host: String? = nil) async -> Int? {
        guard let base = host ?? apiBaseURL else { return nil }
        let scheme = base.hasPrefix("https://") ? "https" : "http"
        let hostWithoutScheme = base.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        guard let url = URL(string: "\(scheme)://\(hostWithoutScheme)/api/ps") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            let ps = try JSONDecoder().decode(OllamaPSResponse.self, from: data)
            return ps.models.count
        } catch {
            print("/api/psの取得に失敗: \(error.localizedDescription)")
            return nil
        }
    }

    /// 現在メモリにロードされているモデルのリストを取得します。
    func fetchRunningModels(host: String? = nil) async -> [OllamaRunningModel]? {
        guard let base = host ?? apiBaseURL else { return nil }
        let scheme = base.hasPrefix("https://") ? "https" : "http"
        let hostWithoutScheme = base.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        guard let url = URL(string: "\(scheme)://\(hostWithoutScheme)/api/ps") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            let ps = try JSONDecoder().decode(OllamaPSResponse.self, from: data)
            return ps.models
        } catch {
            print("/api/psの取得に失敗: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Ollamaの /api/chat エンドポイントにリクエストを送信し、ストリーミングレスポンスを処理します。
    /// - Parameter chatRequest: 送信するChatRequestオブジェクト。
    /// - Returns: ChatResponseChunkのAsyncThrowingStream。
    func chat(model: String, messages: [ChatMessage], stream: Bool, useCustomChatSettings: Bool, isTemperatureEnabled: Bool, chatTemperature: Double, isContextWindowEnabled: Bool, contextWindowValue: Double, isSystemPromptEnabled: Bool, systemPrompt: String, thinkingOption: ThinkingOption, tools: [ToolDefinition]?) -> AsyncThrowingStream<ChatResponseChunk, Error> {
        return AsyncThrowingStream { continuation in
            Task { @MainActor in // Ensure this runs on MainActor to update UI properties safely
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
                    print("DEBUG: useCustomChatSettings: \(useCustomChatSettings), isTemperatureEnabled: \(isTemperatureEnabled), chatTemperature: \(chatTemperature), isContextWindowEnabled: \(isContextWindowEnabled), contextWindowValue: \(contextWindowValue), isSystemPromptEnabled: \(isSystemPromptEnabled), systemPrompt: \(systemPrompt), thinkingOption: \(thinkingOption)")
                    var chatOptions: ChatRequestOptions?
                    if useCustomChatSettings {
                        var options = ChatRequestOptions()
                        if isTemperatureEnabled {
                            options.temperature = chatTemperature
                        }
                        if isContextWindowEnabled {
                            options.numCtx = Int(contextWindowValue) // DoubleをIntにキャスト
                        }
                        chatOptions = options
                        print("DEBUG: Constructed chatOptions.temperature: \(chatOptions?.temperature ?? -1), numCtx: \(chatOptions?.numCtx ?? -1)")
                    }
                    
                    var finalMessages = messages
                    if useCustomChatSettings && isSystemPromptEnabled && !systemPrompt.isEmpty {
                        // Check if a system message already exists
                        if finalMessages.firstIndex(where: { $0.role == "system" }) != nil {
                            // It's generally better to modify the existing one if needed, but for now we assume it's correctly set up by ChatView
                        } else {
                            // Or insert a new one if it doesn't exist
                            finalMessages.insert(ChatMessage(role: "system", content: systemPrompt), at: 0)
                        }
                    }
                    
                    let chatRequest: ChatRequest
                    switch thinkingOption {
                    case .none:
                        chatRequest = ChatRequest(model: model, messages: finalMessages, stream: stream, think: nil, options: chatOptions, tools: tools)
                    case .on:
                        chatRequest = ChatRequest(model: model, messages: finalMessages, stream: stream, think: true, options: chatOptions, tools: tools)
                    case .off:
                        chatRequest = ChatRequest(model: model, messages: finalMessages, stream: stream, think: false, options: chatOptions, tools: tools)
                    }
                    
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted // デバッグ用に整形
                    request.httpBody = try encoder.encode(chatRequest)
                    print("DEBUG: Final Chat Request Body: \(String(data: request.httpBody!, encoding: .utf8) ?? "Invalid Body")")
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                
                let task = urlSession.dataTask(with: request)
                self.chatContinuations[task] = (continuation: continuation, isStreaming: stream)
                self.chatLineBuffers[task] = "" // Initialize buffer for this task
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

    /// チャット履歴と入力テキストをクリアします。
    func clearChat() {
        chatMessages.removeAll()
        chatInputText = ""
        // 関連するストリーミング状態などもリセットする必要があればここに追加
        cancelChatStreaming()
    }
    // これらのメソッドは非同期プロトコル要件を満たすために nonisolated を使用します
    // UI更新は Task { @MainActor in ... } でメインアクターにディスパッチします
    
    /// URLSessionDataDelegateのdidReceiveResponseメソッドです。
    /// このメソッドは、URLSessionTaskDelegateのurlSession(_:task:didReceive:completionHandler:)と名前が似ているため、
    /// Swiftコンパイラが「nearly matches optional requirement」警告を出すことがあります。
    /// `@preconcurrency`属性がクラスに付与されている場合、この警告は抑制されるべきですが、
    /// 特定のSwiftバージョンやビルド設定によっては表示され続けることがあります。
    /// これは機能的な問題ではなく、コンパイラの振る舞いによるものです。
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        Task { @MainActor [weak self, completionHandler] in // completionHandlerをキャプチャリストに追加
            guard let self = self else {
                completionHandler(.cancel)
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
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
                self.pullStatus = NSLocalizedString("Failed", comment: "プルステータス: 失敗。")
                self.isPullingErrorHold = true
                self.isPulling = false
                completionHandler(.cancel)
                return
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
                    print("エラー: 受信データをUTF-8文字列としてデコードできませんでした。")
                    return
                }
                
                var lines = self.pullLineBuffer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                
                if !self.pullLineBuffer.hasSuffix("\n") && !lines.isEmpty {
                    self.pullLineBuffer = lines.removeLast()
                } else {
                    self.pullLineBuffer = ""
                }
                
                for line in lines {
                    guard !line.isEmpty else { continue } // 空行はスキップします
                    guard let jsonData = line.data(using: .utf8) else {
                        print("エラー: 行をDataに変換できませんでした: \(line)")
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
                        
                        print("プルステータス: \(self.pullStatus), 完了: \(self.pendingPullCompleted), 合計: \(self.pendingPullTotal), 進捗: \(String(format: "%.2f", self.pendingPullProgress))")
                    } catch {
                        if let debugString = String(data: jsonData, encoding: .utf8) {
                            print("プルストリームJSONのデコードエラー: \(error.localizedDescription) - 行: \(debugString)")
                            if debugString.contains("\"error\":") || debugString.lowercased().contains("error") {
                                self.output = debugString
                                self.pullHasError = true
                                self.pullStatus = NSLocalizedString("Error", comment: "プルステータス: エラー。")
                                self.isPullingErrorHold = true
                            }                        } else {
                                print("プルストリームJSONのデコードエラー: \(error.localizedDescription) - 行データが読み取り不能です。")
                            }
                    }
                }
            } else if let (continuation, isStreaming) = self.chatContinuations[dataTask] {
                if isStreaming {
                    // ストリーミングチャットの処理
                    if let newString = String(data: data, encoding: .utf8) {
                        self.chatLineBuffers[dataTask, default: ""].append(newString)
                    } else {
                        print("エラー: 受信データをUTF-8文字列としてデコードできませんでした。")
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
                            print("エラー: 行をDataに変換できませんでした: \(line)")
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
                    if self.pullHasError || self.pullStatus == NSLocalizedString("Error", comment: "プルステータス: エラー。") || self.pullStatus == NSLocalizedString("Failed", comment: "プルステータス: 失敗。") {
                        print("保持: pullエラー状態のためオーバーレイ維持。error=\(error.localizedDescription)")
                        self.isPullingErrorHold = true
                        return
                    }
                    self.output = NSLocalizedString("Model pull failed: ", comment: "モデルプルの失敗プレフィックス。") + error.localizedDescription
                    self.pullStatus = NSLocalizedString("Failed", comment: "プルステータス: 失敗。")
                    self.isPullingErrorHold = true
                    print("モデルプルがエラーで失敗しました: \(error.localizedDescription)")
                    self.isPulling = false
                } else {
                    if self.pullHasError {
                        print("完了: ただし途中でエラーを検出したためCompletedにしません")
                        self.isPulling = false
                        return
                    }
                    self.output = NSLocalizedString("Model pull completed: ", comment: "モデルプルの完了プレフィックス。") + self.pullStatus
                    self.pullProgress = 1.0
                    self.pullStatus = NSLocalizedString("Completed", comment: "プルステータス: 完了。")
                    print("モデルプルが完了しました。")
                    await self.fetchOllamaModelsFromAPI()
                    self.isPulling = false
                }
            } else if let (continuation, _) = self.chatContinuations[task] {
                // Handle chat task completion
                if let error = error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }
            
            // Clean up resources for the completed task
            self.chatContinuations.removeValue(forKey: task)
            self.chatLineBuffers.removeValue(forKey: task)
            if task == self.currentChatTask {
                self.currentChatTask = nil
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

    var formattedVRAMSize: String? { // Add formattedVRAMSize
        guard let size = size_vram else { return nil }
        let byteCountFormatter = ByteCountFormatter()
        byteCountFormatter.countStyle = .file
        return byteCountFormatter.string(fromByteCount: size)
    }

    // Custom decoding to handle ISO 8601 date string
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
