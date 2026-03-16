import Foundation
import StoreKit
import SwiftUI

/// ユーザーの利用状況を追跡し、適切なタイミングでApp Storeのレビュー依頼を表示するためのマネージャー。
@Observable @MainActor
class ReviewManager {
    static let shared = ReviewManager()
    
    private let userDefaults = UserDefaults.standard
    
    // UserDefaultsのキー
    private enum Keys {
        static let totalActionCount = "ReviewManager_totalActionCount"
        static let dailyActionCount = "ReviewManager_dailyActionCount"
        static let lastActionDate = "ReviewManager_lastActionDate"
        static let lastReviewRequestDate = "ReviewManager_lastReviewRequestDate"
        static let lastVersionPrompted = "ReviewManager_lastVersionPrompted"
        static let updateDate = "ReviewManager_updateDate"
        static let lastKnownVersion = "ReviewManager_lastKnownVersion"
    }
    
    // 定数
    private let minActions = 30
    private let maxActions = 1000
    private let dailyLimit = 10
    private let rePromptDays = 90
    private let postUpdateGraceDays = 3
        private init() {
        self.totalActionCount = UserDefaults.standard.integer(forKey: Keys.totalActionCount)
        self.dailyActionCount = UserDefaults.standard.integer(forKey: Keys.dailyActionCount)
        self.updateDate = UserDefaults.standard.object(forKey: Keys.updateDate) as? Date ?? Date()
        self.lastReviewRequestDate = UserDefaults.standard.object(forKey: Keys.lastReviewRequestDate) as? Date
        checkVersionUpdate()
    }
    
    // MARK: - 公開プロパティ（統計情報）
    
    var totalActionCount: Int
    var dailyActionCount: Int
    var updateDate: Date
    var lastReviewRequestDate: Date?
    
    // MARK: - 公開メソッド
    
    /// アクションを記録します（チャット、画像生成、ダウンロード開始など）。
    func logAction() {
        let now = Date()
        let calendar = Calendar.current
        
        // 日付が変わったかチェックして本日のカウントをリセット
        if let lastDate = userDefaults.object(forKey: Keys.lastActionDate) as? Date {
            if !calendar.isDate(lastDate, inSameDayAs: now) {
                dailyActionCount = 0
                userDefaults.set(0, forKey: Keys.dailyActionCount)
            }
        }
        userDefaults.set(now, forKey: Keys.lastActionDate)
        
        // 1日の上限に達していない場合のみ累積カウントを増やす
        if dailyActionCount < dailyLimit {
            dailyActionCount += 1
            userDefaults.set(dailyActionCount, forKey: Keys.dailyActionCount)
            
            if totalActionCount < maxActions {
                totalActionCount += 1
                userDefaults.set(totalActionCount, forKey: Keys.totalActionCount)
            }
        }
    }
    
    /// 条件を満たしている場合、レビュー依頼を表示します。
    /// - Parameter requestReviewAction: SwiftUIの環境変数から取得した `requestReview` アクション。
    func requestReviewIfAppropriate(requestReviewAction: RequestReviewAction) {
        guard canShowReviewRequest() else { return }
        
        let currentVersion = getAppVersion()
        
        // レビュー要求を実行
        requestReviewAction()
        
        // 記録を更新
        let now = Date()
        userDefaults.set(now, forKey: Keys.lastReviewRequestDate)
        userDefaults.set(currentVersion, forKey: Keys.lastVersionPrompted)
        lastReviewRequestDate = now
    }
    
    // MARK: - 判定ロジック
    
    private func canShowReviewRequest() -> Bool {
        // 1. 最低アクション数
        // アクション開始時に判定するため、累積29回（このアクションで30回になる）から許可する
        guard totalActionCount >= minActions - 1 else { return false }
        
        let now = Date()
        
        // 2. 前回の表示から90日以上経過しているか
        if let lastRequestDate = userDefaults.object(forKey: Keys.lastReviewRequestDate) as? Date {
            let daysSinceLastRequest = Calendar.current.dateComponents([.day], from: lastRequestDate, to: now).day ?? 0
            guard daysSinceLastRequest >= rePromptDays else { return false }
        }
        
        // 3. アップデートから3日以上経過しているか
        if let updateDate = userDefaults.object(forKey: Keys.updateDate) as? Date {
            let daysSinceUpdate = Calendar.current.dateComponents([.day], from: updateDate, to: now).day ?? 0
            guard daysSinceUpdate >= postUpdateGraceDays else { return false }
        }
        
        // 4. 現在のバージョンでまだ表示していないか
        let currentVersion = getAppVersion()
        let lastVersionPrompted = userDefaults.string(forKey: Keys.lastVersionPrompted) ?? ""
        guard lastVersionPrompted != currentVersion else { return false }
        
        return true
    }
    
    private func checkVersionUpdate() {
        let currentVersion = getAppVersion()
        let lastKnownVersion = userDefaults.string(forKey: Keys.lastKnownVersion) ?? ""
        
        if currentVersion != lastKnownVersion {
            let now = Date()
            userDefaults.set(currentVersion, forKey: Keys.lastKnownVersion)
            userDefaults.set(now, forKey: Keys.updateDate)
            updateDate = now
        }
    }
    
    private func getAppVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
    
    // MARK: - デバッグ用メソッド
    
    #if DEBUG
    func debugAddActions(count: Int) {
        totalActionCount = min(totalActionCount + count, maxActions)
        userDefaults.set(totalActionCount, forKey: Keys.totalActionCount)
        
        // デイリーカウントは上限（10）を超えない範囲で増やす（テストを妨げないため）
        dailyActionCount = min(dailyActionCount + count, dailyLimit - 1)
        userDefaults.set(dailyActionCount, forKey: Keys.dailyActionCount)
    }
    
    func debugResetDailyCount() {
        dailyActionCount = 0
        userDefaults.set(0, forKey: Keys.dailyActionCount)
    }
        func debugResetStats() {
        totalActionCount = 0
        dailyActionCount = 0
        lastReviewRequestDate = nil
        let now = Date()
        updateDate = now
        userDefaults.removeObject(forKey: Keys.totalActionCount)
        userDefaults.removeObject(forKey: Keys.dailyActionCount)
        userDefaults.removeObject(forKey: Keys.lastActionDate)
        userDefaults.removeObject(forKey: Keys.lastReviewRequestDate)
        userDefaults.removeObject(forKey: Keys.lastVersionPrompted)
        userDefaults.removeObject(forKey: Keys.updateDate)
        userDefaults.removeObject(forKey: Keys.lastKnownVersion)
        checkVersionUpdate()
    }
    
    func debugClearLastReviewDate() {
        userDefaults.removeObject(forKey: Keys.lastReviewRequestDate)
        userDefaults.removeObject(forKey: Keys.lastVersionPrompted)
        lastReviewRequestDate = nil
    }
    
    func debugSkipUpdateGracePeriod() {
        let fourDaysAgo = Calendar.current.date(byAdding: .day, value: -4, to: Date()) ?? Date()
        userDefaults.set(fourDaysAgo, forKey: Keys.updateDate)
        updateDate = fourDaysAgo
    }
    
    func debugForceRequestReview(requestReviewAction: RequestReviewAction) {
        requestReviewAction()
        
        // デバッグ時も日付を記録して表示を更新する
        let now = Date()
        let currentVersion = getAppVersion()
        userDefaults.set(now, forKey: Keys.lastReviewRequestDate)
        userDefaults.set(currentVersion, forKey: Keys.lastVersionPrompted)
        lastReviewRequestDate = now
    }
    #endif
}
