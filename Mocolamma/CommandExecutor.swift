import Foundation
import SwiftUI // @Published を使うため

@preconcurrency @MainActor // @preconcurrency を追加して、URLSessionDelegateのデリゲートメソッドに関する警告を抑制
class CommandExecutor: NSObject, ObservableObject, URLSessionDelegate, URLSessionDataDelegate {
    @Published var output: String = "" // 公開用の生のコマンド出力（stdout + stderr + 終了メッセージ）
    @Published var isRunning: Bool = false
    @Published var models: [OllamaModel] = [] // 解析されたモデルリスト

    // モデルプル時の進捗状況
    @Published var isPulling: Bool = false
    @Published var pullStatus: String = NSLocalizedString("準備中...", comment: "Pull status: preparing.")
    @Published var pullProgress: Double = 0.0 // 0.0 から 1.0
    @Published var pullTotal: Int64 = 0 // 合計バイト数
    @Published var pullCompleted: Int64 = 0 // 完了したバイト数

    private var urlSession: URLSession!
    private var pullTask: URLSessionDataTask?
    private var pullLineBuffer = "" // 不完全なJSON行を保持する文字列バッファ

    override init() {
        super.init()
        // デリゲートキューをnilに設定し、デリゲートメソッドがバックグラウンドスレッドで実行されるようにします
        // デリゲートメソッド内で @MainActor への切り替えをTask { @MainActor in ... } で明示的に行う
        let configuration = URLSessionConfiguration.default
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// Ollama APIからモデルリストを取得する (async/await版)
    func fetchOllamaModelsFromAPI() async {
        print("Fetching Ollama API models...")
        // UI更新はメインアクターで行う
        self.output = NSLocalizedString("モデルをAPIから取得中...", comment: "Status message when fetching models from API.")
        self.isRunning = true

        // defer で isRunning を false に設定し、関数終了時に必ず実行されるようにする
        defer {
            self.isRunning = false
        }

        guard let url = URL(string: "http://localhost:11434/api/tags") else {
            self.output = NSLocalizedString("エラー: 無効なAPI URLです。", comment: "Error message for invalid API URL.")
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                self.output = NSLocalizedString("APIエラー: 不明なレスポンスタイプです。", comment: "Error message for unknown API response type.")
                print("API Error: Invalid response type.")
                return
            }

            guard httpResponse.statusCode == 200 else {
                let statusMessage = String(format: NSLocalizedString("APIエラー: HTTPステータスコード %d", comment: "Error message for HTTP status code."), httpResponse.statusCode)
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
            let successMessage = String(format: NSLocalizedString("モデルの取得に成功しました。合計: %d", comment: "Success message for fetching models."), self.models.count)
            self.output = successMessage
            print("Models fetched successfully. Total: \(self.models.count)")

        } catch let decodingError as DecodingError {
            self.output = NSLocalizedString("APIデコードエラー: ", comment: "API decode error prefix.") + decodingError.localizedDescription
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
            self.output = NSLocalizedString("APIリクエストエラー: ", comment: "API request error prefix.") + error.localizedDescription
            print("API Request Error (other): \(error.localizedDescription)")
        }
    }

    /// モデルをダウンロードする (Delegateを使うため async化はしないが、UI更新は @MainActor にディスパッチ)
    func pullModel(modelName: String) {
        print("Attempting to pull model: \(modelName)")
        // UI更新はメインアクターで行う
        self.output = String(format: NSLocalizedString("モデル '%@' をダウンロード中...", comment: "Status message when downloading model."), modelName)
        self.isPulling = true
        self.pullStatus = NSLocalizedString("準備中...", comment: "Pull status: preparing.")
        self.pullProgress = 0.0
        self.pullTotal = 0
        self.pullCompleted = 0

        guard let url = URL(string: "http://localhost:11434/api/pull") else {
            self.output = NSLocalizedString("エラー: プル用のAPI URLが無効です。", comment: "Error message for invalid pull API URL.")
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
            self.output = NSLocalizedString("エラー: プルリクエストのボディのシリアライズに失敗しました: ", comment: "Error message for failed pull request body serialization.") + error.localizedDescription
            self.isPulling = false
            return
        }

        pullTask?.cancel()
        pullTask = urlSession.dataTask(with: request)
        pullTask?.resume()
    }

    /// モデルを削除する
    func deleteModel(modelName: String) async {
        print("Attempting to delete model: \(modelName)")
        // UI更新はメインアクターで行う
        self.output = String(format: NSLocalizedString("モデル '%@' を削除中...", comment: "Status message when deleting model."), modelName)
        self.isRunning = true

        defer { self.isRunning = false }

        guard let url = URL(string: "http://localhost:11434/api/delete") else {
            self.output = NSLocalizedString("エラー: 削除用のAPI URLが無効です。", comment: "Error message for invalid delete API URL.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["model": modelName]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            self.output = NSLocalizedString("エラー: リクエストボディのシリアライズに失敗しました: ", comment: "Error message for failed request body serialization.") + error.localizedDescription
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                self.output = NSLocalizedString("削除エラー: 不明なレスポンスタイプです。", comment: "Error message for unknown delete response type.")
                print("Delete Error: Unknown response type.")
                return
            }

            if httpResponse.statusCode == 200 {
                self.output = String(format: NSLocalizedString("モデル '%@' を正常に削除しました。", comment: "Success message for model deletion."), modelName)
                print("Model '\(modelName)' deleted successfully.")
                await self.fetchOllamaModelsFromAPI() // メインアクターで実行されるasync関数なので直接呼び出し可能

            } else if httpResponse.statusCode == 404 {
                self.output = String(format: NSLocalizedString("削除エラー: モデル '%@' が見つかりません (404 Not Found)。", comment: "Error message for model not found during deletion."), modelName)
                print("Delete Error: Model '\(modelName)' not found (404).")
            } else {
                let errorString = String(data: data, encoding: .utf8) ?? NSLocalizedString("データなし", comment: "No data available.")
                let errorMessage = String(format: NSLocalizedString("削除エラー: HTTP ステータスコード %d - %@", comment: "Error message for HTTP status code during deletion."), httpResponse.statusCode, errorString)
                self.output = errorMessage
                print("Delete Error: HTTP Status Code \(httpResponse.statusCode) - \(errorString)")
            }
        } catch {
            self.output = NSLocalizedString("モデル削除失敗: ", comment: "Model deletion failed prefix.") + error.localizedDescription
            print("Model delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - URLSessionDataDelegate Methods (バックグラウンドスレッドで呼び出される)
    // これらのメソッドは非同期プロトコル要件を満たすために nonisolated を使用
    // UI更新は Task { @MainActor in ... } でメインアクターにディスパッチ

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
                self.output = String(format: NSLocalizedString("モデルプルエラー: HTTPステータスコード %d", comment: "Model pull error: HTTP status code."), (response as? HTTPURLResponse)?.statusCode ?? -1)
                self.isPulling = false
                self.pullStatus = NSLocalizedString("エラー", comment: "Pull status: error.")
                completionHandler(.cancel)
                return
            }
            self.pullLineBuffer = "" // 新しいレスポンスが来たのでバッファをクリア
            completionHandler(.allow)
        }
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            // 受信したデータを既存のバッファに追加
            if let newString = String(data: data, encoding: .utf8) {
                self.pullLineBuffer.append(newString)
            } else {
                print("Error: Could not decode incoming data as UTF-8 string.")
                return
            }
            
            // バッファを改行で分割し、完全な行を処理
            var lines = self.pullLineBuffer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            
            // 最後の行が改行で終わっていない場合（不完全な行）、それをバッファに残す
            if !self.pullLineBuffer.hasSuffix("\n") && !lines.isEmpty {
                self.pullLineBuffer = lines.removeLast()
            } else {
                self.pullLineBuffer = ""
            }

            // 各完全なJSON行を処理
            for line in lines {
                guard !line.isEmpty else { continue } // 空行はスキップ
                guard let jsonData = line.data(using: .utf8) else {
                    print("Error: Could not convert line to Data: \(line)")
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
                        self.pullProgress = Double(self.pullCompleted) / Double(self.pullTotal)
                    } else {
                        self.pullProgress = 0.0
                    }
                    
                    print("Pull Status: \(self.pullStatus), Completed: \(self.pullCompleted), Total: \(self.pullTotal), Progress: \(self.pullProgress)")
                } catch {
                    if let debugString = String(data: jsonData, encoding: .utf8) {
                        print("Error decoding pull stream JSON: \(error.localizedDescription) - Line: \(debugString)")
                    } else {
                        print("Error decoding pull stream JSON: \(error.localizedDescription) - Line data unreadable.")
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
                self.output = NSLocalizedString("モデルプル失敗: ", comment: "Model pull failed prefix.") + error.localizedDescription
                self.isPulling = false
                self.pullStatus = NSLocalizedString("失敗", comment: "Pull status: failed.")
                print("Model pull failed with error: \(error.localizedDescription)")
            } else {
                self.output = NSLocalizedString("モデルプル完了: ", comment: "Model pull completed prefix.") + self.pullStatus
                self.isPulling = false
                self.pullProgress = 1.0
                self.pullStatus = NSLocalizedString("完了", comment: "Pull status: completed.")
                print("Model pull completed.")
                // モデルリストを更新するために API から再取得
                await self.fetchOllamaModelsFromAPI()
            }
        }
    }
}

// MARK: - Ollama API Response Models

struct OllamaAPIModelsResponse: Decodable {
    let models: [OllamaModel]
}

struct OllamaPullResponse: Decodable {
    let status: String
    let digest: String?
    let total: Int64?
    let completed: Int64?
}
