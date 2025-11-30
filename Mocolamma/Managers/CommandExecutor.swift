import Foundation
import SwiftUI
import Combine

@preconcurrency @MainActor
class CommandExecutor: NSObject, ObservableObject, URLSessionDelegate, URLSessionDataDelegate {
    @Published var output: String = ""
    @Published var isRunning: Bool = false
    @Published var pullHttpErrorTriggered: Bool = false
    @Published var pullHttpErrorMessage: String = ""
    @Published var models: [OllamaModel] = []
    @Published var apiConnectionError: Bool = false
    @Published var specificConnectionErrorMessage: String?
    @Published var chatMessages: [ChatMessage] = []
    @Published var chatInputText: String = ""
    @Published var isChatStreaming: Bool = false
    
    // モデルプル時の進捗状況
    @Published var isPulling: Bool = false
    @Published var isPullingErrorHold: Bool = false
    @Published var pullHasError: Bool = false
    @Published var pullStatus: String = "Preparing..." // プルステータス: 準備中。
    @Published var pullProgress: Double = 0.0 // 0.0 から 1.0
    @Published var pullTotal: Int64 = 0 // 合計バイト数
    @Published var pullCompleted: Int64 = 0 // 完了したバイト数
    @Published var pullSpeedBytesPerSec: Double = 0.0 // 現在のダウンロード速度 (B/s)
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
    @Published var apiBaseURL: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - モデル情報キャッシュ
    private var modelInfoCache: [String: OllamaShowResponse] = [:]
    
    // isChatStreamingを更新する関数
    func updateIsChatStreaming() {
        isChatStreaming = chatMessages.firstIndex { $0.isStreaming } != nil
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
        
        // ServerManagerのcurrentServerHostの変更を監視し、apiBaseURLを更新
        serverManager.$servers
            .map { servers in
                // serversリストが変更された場合、selectedServerIDに基づき新しいcurrentServerHostを計算
                // selectedServerIDがない場合や、対応するサーバーがserversにない場合を考慮
                if let selectedID = serverManager.selectedServerID,
                   let selectedServer = servers.first(where: { $0.id == selectedID }) {
                    return selectedServer.host
                }
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
            let (data, response) = try await URLSession.shared.data(from: url)
            
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
            self.models = apiResponse.models.enumerated().map { (index, model) in
                var mutableModel = model
                mutableModel.originalIndex = index
                return mutableModel
            }
            let successMessage = String(format: NSLocalizedString("Successfully fetched models. Total: %d", comment: "Ollamaサーバー上からモデル情報を取得することができた場合のメッセージ。合計モデル数。"), self.models.count)
            self.output = successMessage
            print("Successfully retrieved models. Total: \(self.models.count)")
            self.apiConnectionError = false // 成功時はエラーなし
            
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
    
    /// モデルを削除します
    func deleteModel(modelName: String) async {
        guard let apiBaseURL = self.apiBaseURL else {
            print("Ollama API base URL is not set. Skipping model deletion.")
            self.output = NSLocalizedString("Error: No Ollama server selected.", comment: "Ollamaサーバーからモデルを削除しようとした際にモデルが選択されていなかった場合に表示されるイランメッセージ。")
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
            let (data, response) = try await URLSession.shared.data(for: request)
            
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
    
    /// モデルの詳細情報を取得します
    func fetchModelInfo(modelName: String) async -> OllamaShowResponse? {
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
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("API Error: /api/show - HTTP status code \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            
            let apiResponse = try JSONDecoder().decode(OllamaShowResponse.self, from: data)
            print("Successfully retrieved model \(modelName) details.")
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
        let scheme = host.hasPrefix("https://") ? "https" : "http"
        let hostWithoutScheme = host.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        guard let url = URL(string: "\(scheme)://\(hostWithoutScheme)/api/tags") else {
            print("Connection check error: Invalid URL for host \(host)")
            return .unknownHost
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
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
            print("Connection check error to \(host): \(error.localizedDescription)")
            // タイムアウトエラーのチェック
            if error.code == .timedOut {
                return .timedOut
            }
            // TLSエラーのチェック
            if scheme == "https" && (
                error.code == .secureConnectionFailed ||
                error.code == .serverCertificateUntrusted ||
                error.code == .cannotConnectToHost || // 接続できない場合もTLS関連の可能性あり
                error.code == .networkConnectionLost // 接続が失われた場合もTLS関連の可能性あり
            ) {
                self.specificConnectionErrorMessage = NSLocalizedString("Could not connect to API.\nTLS error occurred, could not establish a secure connection.", comment: "TLS接続エラー時のメッセージ。")
            } else {
                self.specificConnectionErrorMessage = nil // 他のエラーの場合はクリア
            }
            return .unknownHost
        } catch {
            print("Connection check error to \(host): \(error.localizedDescription)")
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
        print("Model information cache cleared.")
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
            print("Failed to retrieve /api/ps: \(error.localizedDescription)")
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
            print("Failed to retrieve /api/ps: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Ollamaの /api/chat エンドポイントにリクエストを送信し、ストリーミングレスポンスを処理します。
    /// - Parameter chatRequest: 送信するChatRequestオブジェクト。
    /// - Returns: ChatResponseChunkのAsyncThrowingStream。
    func chat(model: String, messages: [ChatMessage], stream: Bool, useCustomChatSettings: Bool, isTemperatureEnabled: Bool, chatTemperature: Double, isContextWindowEnabled: Bool, contextWindowValue: Double, isSystemPromptEnabled: Bool, systemPrompt: String, thinkingOption: ThinkingOption, tools: [ToolDefinition]?) -> AsyncThrowingStream<ChatResponseChunk, Error> {
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
    
    /// チャット履歴と入力テキストをクリアします。
    func clearChat() {
        chatMessages.removeAll()
        chatInputText = ""
        updateIsChatStreaming()
        cancelChatStreaming()
    }
    
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        Task { @MainActor [weak self, completionHandler] in
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
                self.pullStatus = NSLocalizedString("Failed", comment: "失敗")
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
                            }                        } else {
                                print("Pull stream JSON decode error: \(error.localizedDescription) - Line data unreadable.")
                            }
                    }
                }
            } else if let (continuation, isStreaming) = self.chatContinuations[dataTask] {
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
            }
            
            // 完了したタスクのリソースをクリーンアップ
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
    
    var formattedVRAMSize: String? { // VRAMサイズをフォーマット
        guard let size = size_vram else { return nil }
        let byteCountFormatter = ByteCountFormatter()
        byteCountFormatter.countStyle = .file
        return byteCountFormatter.string(fromByteCount: size)
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
