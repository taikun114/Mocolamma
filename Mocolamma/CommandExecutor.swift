import Foundation
import SwiftUI // @Published を使うため

@preconcurrency @MainActor // @preconcurrency を追加して、URLSessionDelegateのデリゲートメソッドに関する警告を抑制します
class CommandExecutor: NSObject, ObservableObject, URLSessionDelegate, URLSessionDataDelegate {
    @Published var output: String = "" // 公開用の生のコマンド出力（stdout + stderr + 終了メッセージ）
    @Published var isRunning: Bool = false
    @Published var models: [OllamaModel] = [] // 解析されたモデルリスト

    // モデルプル時の進捗状況
    @Published var isPulling: Bool = false
    @Published var pullStatus: String = "Preparing..." // プルステータス: 準備中。
    @Published var pullProgress: Double = 0.0 // 0.0 から 1.0
    @Published var pullTotal: Int64 = 0 // 合計バイト数
    @Published var pullCompleted: Int64 = 0 // 完了したバイト数

    private var urlSession: URLSession!
    private var pullTask: URLSessionDataTask?
    private var pullLineBuffer = "" // 不完全なJSON行を保持する文字列バッファ

    override init() {
        super.init()
        // デリゲートキューをnilに設定し、デリゲートメソッドがバックグラウンドスレッドで実行されるようにします
        // デリゲートメソッド内で @MainActor への切り替えをTask { @MainActor in ... } で明示的に行います
        let configuration = URLSessionConfiguration.default
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// Ollama APIからモデルリストを取得します (async/await版)
    func fetchOllamaModelsFromAPI() async {
        print("Fetching Ollama API models...")
        // UI更新はメインアクターで行います
        self.output = "Fetching models from API..." // APIからモデルを取得中のステータスメッセージ。
        self.isRunning = true

        // defer を使って関数終了時に必ず isRunning を false に設定します
        defer {
            self.isRunning = false
        }

        guard let url = URL(string: "http://localhost:11434/api/tags") else {
            self.output = "Error: Invalid API URL." // 無効なAPI URLのエラーメッセージ。
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                self.output = "API Error: Unknown response type." // 不明なAPIレスポンスタイプのエラーメッセージ。
                print("API Error: Invalid response type.")
                return
            }

            guard httpResponse.statusCode == 200 else {
                let statusMessage = String(format: "API Error: HTTP Status Code %d", httpResponse.statusCode) // HTTPステータスコードのエラーメッセージ。
                self.output = statusMessage
                print("API Error: HTTP Status Code \(httpResponse.statusCode)")
                if let errorString = String(data: data, encoding: .utf8) {
                    print("API Error Response: \(errorString)")
                }
                return
            }
            
            print("Attempting to decode. Data size: \(data.count) bytes. First 10 bytes: \(data.prefix(10).map { String(format: "%02x", $0) }.joined())")

            let apiResponse = try JSONDecoder().decode(OllamaAPIModelsResponse.self, from: data)
            self.models = apiResponse.models.enumerated().map { (index, model) in
                var mutableModel = model
                mutableModel.originalIndex = index
                return mutableModel
            }
            let successMessage = String(format: "Successfully fetched models. Total: %d", self.models.count) // モデル取得成功のメッセージ。
            self.output = successMessage
            print("Models fetched successfully. Total: \(self.models.count)")

        } catch let decodingError as DecodingError {
            self.output = "API Decode Error: " + decodingError.localizedDescription // APIデコードエラーのプレフィックス。
            print("API Decode Error: \(decodingError.localizedDescription)")

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
            self.output = "API Request Error: " + error.localizedDescription // APIリクエストエラーのプレフィックス。
            print("API Request Error (other): \(error.localizedDescription)")
        }
    }

    /// モデルをダウンロードします (デリゲートを使用するため async化はしませんが、UI更新は @MainActor にディスパッチします)
    func pullModel(modelName: String) {
        print("Attempting to pull model: \(modelName)")
        // UI更新はメインアクターで行います
        self.output = String(format: "Downloading model '%@'...", modelName) // モデルダウンロード中のステータスメッセージ。
        self.isPulling = true
        self.pullStatus = "Preparing..." // プルステータス: 準備中。
        self.pullProgress = 0.0
        self.pullTotal = 0
        self.pullCompleted = 0

        guard let url = URL(string: "http://localhost:11434/api/pull") else {
            self.output = "Error: Invalid API URL for pull." // プル用API URLが無効な場合のエラーメッセージ。
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
            self.output = "Error: Failed to serialize pull request body: " + error.localizedDescription // プルリクエストボディのシリアライズ失敗のエラーメッセージ。
            self.isPulling = false
            return
        }

        pullTask?.cancel()
        pullTask = urlSession.dataTask(with: request)
        pullTask?.resume()
    }

    /// モデルを削除します
    func deleteModel(modelName: String) async {
        print("Attempting to delete model: \(modelName)")
        // UI更新はメインアクターで行います
        self.output = String(format: "Deleting model '%@'...", modelName) // モデル削除中のステータスメッセージ。
        self.isRunning = true

        defer { self.isRunning = false }

        guard let url = URL(string: "http://localhost:11434/api/delete") else {
            self.output = "Error: Invalid API URL for delete." // 削除用API URLが無効な場合のエラーメッセージ。
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["model": modelName]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            self.output = "Error: Failed to serialize request body: " + error.localizedDescription // リクエストボディのシリアライズ失敗のエラーメッセージ。
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                self.output = "Delete Error: Unknown response type." // 削除エラー: 不明なレスポンスタイプのエラーメッセージ。
                print("Delete Error: Unknown response type.")
                return
            }

            if httpResponse.statusCode == 200 {
                self.output = String(format: "Successfully deleted model '%@'.", modelName) // モデル削除成功のメッセージ。
                print("Model '\(modelName)' deleted successfully.")
                await self.fetchOllamaModelsFromAPI() // メインアクターで実行されるasync関数なので直接呼び出し可能です

            } else if httpResponse.statusCode == 404 {
                self.output = String(format: "Delete Error: Model '%@' not found (404 Not Found).", modelName) // 削除エラー: モデルが見つからない場合のエラーメッセージ。
                print("Delete Error: Model '\(modelName)' not found (404).")
            } else {
                let errorString = String(data: data, encoding: .utf8) ?? "No data available" // データなし。
                let errorMessage = String(format: "Delete Error: HTTP Status Code %d - %@", httpResponse.statusCode, errorString) // 削除エラー: HTTPステータスコードのエラーメッセージ。
                self.output = errorMessage
                print("Delete Error: HTTP Status Code \(httpResponse.statusCode) - \(errorString)")
            }
        } catch {
            self.output = "Model deletion failed: " + error.localizedDescription // モデル削除失敗のプレフィックス。
            print("Model delete failed: \(error.localizedDescription)")
        }
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
                self.output = String(format: "Model pull error: HTTP Status Code %d", (response as? HTTPURLResponse)?.statusCode ?? -1) // モデルプルエラー: HTTPステータスコード。
                self.isPulling = false
                self.pullStatus = "Error" // プルステータス: エラー。
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
                print("Error: Could not decode incoming data as UTF-8 string.") // エラー: 受信データをUTF-8文字列としてデコードできませんでした。
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
                    print("Error: Could not convert line to Data: \(line)") // エラー: 行をDataに変換できませんでした。
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
                    
                    print("Pull Status: \(self.pullStatus), Completed: \(self.pullCompleted), Total: \(self.pullTotal), Progress: \(self.pullProgress)") // プルステータス、完了、合計、進捗
                } catch {
                    if let debugString = String(data: jsonData, encoding: .utf8) {
                        print("Error decoding pull stream JSON: \(error.localizedDescription) - Line: \(debugString)") // プルストリームJSONのデコードエラー。
                    } else {
                        print("Error decoding pull stream JSON: \(error.localizedDescription) - Line data unreadable.") // プルストリームJSONのデコードエラー。行データが読み取り不能です。
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
                self.output = "Model pull failed: " + error.localizedDescription // モデルプルの失敗プレフィックス。
                self.isPulling = false
                self.pullStatus = "Failed" // プルステータス: 失敗。
                print("Model pull failed with error: \(error.localizedDescription)") // モデルプルがエラーで失敗しました。
            } else {
                self.output = "Model pull completed: " + self.pullStatus // モデルプルの完了プレフィックス。
                self.isPulling = false
                self.pullProgress = 1.0
                self.pullStatus = "Completed" // プルステータス: 完了。
                print("Model pull completed.") // モデルプルが完了しました。
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

struct OllamaPullResponse: Decodable {
    let status: String
    let digest: String?
    let total: Int64?
    let completed: Int64?
}
