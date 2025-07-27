import Foundation
import SwiftUI // @Published を使うため
import Combine // CombineフレームワークをインポートしてPublisherを購読可能にする

@preconcurrency @MainActor // @preconcurrency を追加して、URLSessionDelegateのデリゲートメソッドに関する警告を抑制します
class CommandExecutor: NSObject, ObservableObject, URLSessionDelegate, URLSessionDataDelegate {
    @Published var output: String = "" // 公開用の生のコマンド出力（stdout + stderr + 終了メッセージ）
    @Published var isRunning: Bool = false
    @Published var models: [OllamaModel] = [] // 解析されたモデルリスト
    @Published var apiConnectionError: Bool = false // API接続エラーの状態を追加

    // モデルプル時の進捗状況
    @Published var isPulling: Bool = false
    @Published var pullStatus: String = "Preparing..." // プルステータス: 準備中。
    @Published var pullProgress: Double = 0.0 // 0.0 から 1.0
    @Published var pullTotal: Int64 = 0 // 合計バイト数
    @Published var pullCompleted: Int64 = 0 // 完了したバイト数

    private var urlSession: URLSession!
    private var pullTask: URLSessionDataTask?
    private var pullLineBuffer = "" // 不完全なJSON行を保持する文字列バッファ

    // Ollama APIのベースURL
    // ServerManagerから現在のサーバーホストを受け取るように変更
    @Published var apiBaseURL: String

    private var cancellables = Set<AnyCancellable>() // ServerManagerの変更を監視するためのSet

    /// CommandExecutorのイニシャライザ。ServerManagerのインスタンスを受け取り、APIベースURLを監視します。
    /// - Parameter serverManager: サーバーリストと選択状態を管理するServerManagerのインスタンス。
    init(serverManager: ServerManager) {
        // 初期化時にServerManagerから現在のホストURLを設定
        self.apiBaseURL = serverManager.currentServerHost
        super.init()
        // デリゲートキューをnilに設定し、デリゲートメソッドがバックグラウンドスレッドで実行されるようにします
        // デリゲートメソッド内で @MainActor への切り替えをTask { @MainActor in ... } で明示的に行います
        let configuration = URLSessionConfiguration.default
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
                // デフォルトのフォールバック
                return servers.first?.host ?? "localhost:11434"
            }
            .assign(to: \.apiBaseURL, on: self)
            .store(in: &cancellables)

        serverManager.$selectedServerID
            .compactMap { selectedID in
                // selectedServerIDが変更された場合、対応するサーバーのホストを返す
                serverManager.servers.first(where: { $0.id == selectedID })?.host
            }
            .assign(to: \.apiBaseURL, on: self)
            .store(in: &cancellables)
    }

    /// Ollama APIからモデルリストを取得します (async/await版)
    func fetchOllamaModelsFromAPI() async {
        print("Ollama APIから \(apiBaseURL) のモデルリストを取得中...")
        // UI更新はメインアクターで行います
        self.output = String(format: NSLocalizedString("Fetching models from API (%@)...", comment: "APIからモデルを取得中のステータスメッセージ。"), apiBaseURL)
        self.isRunning = true
        self.apiConnectionError = false // 新しいフェッチの前にエラー状態をリセット
        // モデルリストを一旦クリア
        self.models = []

        // defer を使って関数終了時に必ず isRunning を false に設定します
        defer {
            self.isRunning = false
        }

        guard let url = URL(string: "http://\(apiBaseURL)/api/tags") else {
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
            
            print("デコードを試行中。データサイズ: \(data.count) バイト。最初の10バイト: \(data.prefix(10).map { String(format: "%02x", $0) }.joined())")

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
        print("モデル \(modelName) を \(apiBaseURL) からプルを試行中")
        // UI更新はメインアクターで行います
        self.output = String(format: NSLocalizedString("Downloading model '%@' from %@...", comment: "モデルダウンロード中のステータスメッセージ。"), modelName, apiBaseURL)
        self.isPulling = true
        self.pullStatus = NSLocalizedString("Preparing...", comment: "プルステータス: 準備中。")
        self.pullProgress = 0.0
        self.pullTotal = 0
        self.pullCompleted = 0

        guard let url = URL(string: "http://\(apiBaseURL)/api/pull") else {
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
        print("モデル \(modelName) を \(apiBaseURL) から削除を試行中")
        // UI更新はメインアクターで行います
        self.output = String(format: NSLocalizedString("Deleting model '%@' from %@...", comment: "モデル削除中のステータスメッセージ。"), modelName, apiBaseURL)
        self.isRunning = true

        defer { self.isRunning = false }

        guard let url = URL(string: "http://\(apiBaseURL)/api/delete") else {
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
    func fetchModelInfo(modelName: String) async -> [String: JSONValue]? {
        print("モデル \(modelName) の詳細情報を \(apiBaseURL) から取得中...")
        
        guard let url = URL(string: "http://\(apiBaseURL)/api/show") else {
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
            return apiResponse.model_info
            
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
    /// - Returns: 接続に成功した場合はtrue、それ以外はfalse。
    func checkAPIConnectivity(host: String) async -> Bool {
        guard let url = URL(string: "http://\(host)/api/tags") else {
            print("接続確認エラー: ホスト \(host) のURLが無効です")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD" // HEADリクエストでヘッダーのみを取得し、高速化と帯域幅の節約を図る

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("接続確認: \(host) への接続に成功しました")
                return true
            } else {
                print("接続確認: \(host) への接続に失敗しました - HTTPステータスコード: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return false
            }
        } catch {
            print("\(host) への接続確認エラー: \(error.localizedDescription)")
            return false
        }
    }

    /// Ollamaのバージョンを取得します。
    /// - Parameter host: OllamaホストのURL。
    /// - Returns: Ollamaのバージョン文字列。
    func fetchOllamaVersion(host: String) async throws -> String {
        guard let url = URL(string: "http://\(host)/api/version") else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(OllamaVersionResponse.self, from: data)
        return response.version
    }

    // MARK: - URLSessionDataDelegate Methods (バックグラウンドスレッドで呼び出されます)
    // これらのメソッドは非同期プロトコル要件を満たすために nonisolated を使用します
    // UI更新は Task { @MainActor in ... } でメインアクターにディスパッチします

    /// URLSessionDataDelegateのdidReceiveResponseメソッドです。
    /// このメソッドは、URLSessionTaskDelegateのurlSession(_:task:didReceive:completionHandler:)と名前が似ているため、
    /// Swiftコンパイラが「nearly matches optional requirement」警告を出すことがあります。
    /// `@preconcurrency`属性がクラスに付与されている場合、この警告は抑制されるべきですが、
    /// 特定のSwiftバージョンやビルド設定によっては表示され続けることがあります。
    /// これは機能的な問題ではなく、コンパイラの振る舞いによるものです。
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceiveResponse response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        Task { @MainActor [weak self] in
            guard let self = self else {
                completionHandler(.cancel)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                self.output = String(format: NSLocalizedString("Model pull error: HTTP Status Code %d", comment: "モデルプルエラー: HTTPステータスコード。"), (response as? HTTPURLResponse)?.statusCode ?? -1)
                self.isPulling = false
                self.pullStatus = NSLocalizedString("Error", comment: "プルステータス: エラー。")
                completionHandler(.cancel)
                return
            }
            self.pullLineBuffer = "" // 新しいレスポンスが来たのでバッファをクリアします
            completionHandler(.allow)
        }
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            // 受信したデータを既存のバッファに追加します
            if let newString = String(data: data, encoding: .utf8) {
                self.pullLineBuffer.append(newString)
            } else {
                print("エラー: 受信データをUTF-8文字列としてデコードできませんでした。")
                return
            }
            
            // バッファを改行で分割し、完全な行を処理します
            var lines = self.pullLineBuffer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            
            // 最後の行が改行で終わっていない場合（不完全な行）、それをバッファに残します
            if !self.pullLineBuffer.hasSuffix("\n") && !lines.isEmpty {
                self.pullLineBuffer = lines.removeLast()
            } else {
                self.pullLineBuffer = ""
            }

            // 各完全なJSON行を処理します
            for line in lines {
                guard !line.isEmpty else { continue } // 空行はスキップします
                guard let jsonData = line.data(using: .utf8) else {
                    print("エラー: 行をDataに変換できませんでした: \(line)")
                    continue
                }

                do {
                    let response = try JSONDecoder().decode(OllamaPullResponse.self, from: jsonData)
                    self.pullStatus = response.status
                    
                    if let total = response.total {
                        self.pullTotal = total
                    }
                    if let completed = response.completed {
                        self.pullCompleted = completed
                    }
                    
                    if self.pullTotal > 0 {
                        var calculatedProgress = Double(self.pullCompleted) / Double(self.pullTotal)
                        // 進捗値を0.0から1.0の間にクランプします
                        calculatedProgress = min(max(0.0, calculatedProgress), 1.0)
                        self.pullProgress = calculatedProgress
                    } else {
                        self.pullProgress = 0.0
                    }
                    
                    print("プルステータス: \(self.pullStatus), 完了: \(self.pullCompleted), 合計: \(self.pullTotal), 進捗: \(String(format: "%.2f", self.pullProgress))")
                } catch {
                    if let debugString = String(data: jsonData, encoding: .utf8) {
                        print("プルストリームJSONのデコードエラー: \(error.localizedDescription) - 行: \(debugString)")
                    } else {
                        print("プルストリームJSONのデコードエラー: \(error.localizedDescription) - 行データが読み取り不能です。")
                    }
                }
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            self.pullTask = nil
            self.pullLineBuffer = ""

            if let error = error {
                self.output = NSLocalizedString("Model pull failed: ", comment: "モデルプルの失敗プレフィックス。") + error.localizedDescription
                self.isPulling = false
                self.pullStatus = NSLocalizedString("Failed", comment: "プルステータス: 失敗。")
                print("モデルプルがエラーで失敗しました: \(error.localizedDescription)")
            } else {
                self.output = NSLocalizedString("Model pull completed: ", comment: "モデルプルの完了プレフィックス。") + self.pullStatus
                self.isPulling = false
                self.pullProgress = 1.0
                self.pullStatus = NSLocalizedString("Completed", comment: "プルステータス: 完了。")
                print("モデルプルが完了しました。")
                // モデルリストを更新するために API から再取得します
                await self.fetchOllamaModelsFromAPI()
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
    let modelfile: String?
    let parameters: String?
    let template: String?
    let details: OllamaModelDetails?
    let model_info: [String: JSONValue]?
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
