import Foundation

/// 偏好設定 — 存於 App Group UserDefaults，主 app 寫、鍵盤 extension 讀。
struct OhMyBiasPrefs {
    static let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard

    /// 唯一候選且無法再延伸時自動送出
    static var autoCommit: Bool {
        get { defaults.object(forKey: "autoCommit") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "autoCommit") }
    }

    /// 送字後顯示字根碼提示
    static var showCodeHint: Bool {
        get { defaults.object(forKey: "showCodeHint") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "showCodeHint") }
    }

    /// 聯想總開關
    static var suggestEnabled: Bool {
        get { defaults.object(forKey: "suggestEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "suggestEnabled") }
    }

    /// 無候選時嘗試相鄰鍵模糊比對
    static var fuzzyMatch: Bool {
        get { defaults.object(forKey: "fuzzyMatch") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "fuzzyMatch") }
    }

    /// 聯想策略（極簡版僅萌典詞組，維持介面相容）
    static var suggestStrategy: String {
        get { defaults.string(forKey: "suggestStrategy") ?? "general" }
        set { defaults.set(newValue, forKey: "suggestStrategy") }
    }

    /// 詞級語料 — iOS 極簡版只有萌典
    static var wordCorpus: String {
        get { defaults.string(forKey: "wordCorpus") ?? "moedict" }
        set { defaults.set(newValue, forKey: "wordCorpus") }
    }

    /// 字級聯想（bigram/trigram）— 極簡版無字級語料，保留介面
    static var charSuggest: Bool {
        get { defaults.object(forKey: "charSuggest") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "charSuggest") }
    }

    /// 地區用詞：tw / cn（極簡版無地區語料，保留介面）
    static var regionVariant: String {
        get { defaults.string(forKey: "regionVariant") ?? "tw" }
        set { defaults.set(newValue, forKey: "regionVariant") }
    }

    /// 標點配對：打「自動補」（iOS 預設開啟）
    static var punctuationPairing: Bool {
        get { defaults.object(forKey: "punctuationPairing") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "punctuationPairing") }
    }

    /// 同音字查詢包含多音字的罕見讀音
    static var homophoneMultiReading: Bool {
        get { defaults.object(forKey: "homophoneMultiReading") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "homophoneMultiReading") }
    }

    /// 上次使用的語言模式（true = 英文）— 鍵盤啟動時還原
    static var lastEnglishMode: Bool {
        get { defaults.object(forKey: "lastEnglishMode") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "lastEnglishMode") }
    }

    /// 按鍵觸覺回饋
    static var hapticFeedback: Bool {
        get { defaults.object(forKey: "hapticFeedback") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "hapticFeedback") }
    }

    /// 鍵盤高度縮放（0.85–1.40；1.0 = 預設 224pt/180pt）— 大螢幕手機可調大（同 Android 版）
    static var keyboardHeightScale: Double {
        get { min(max(defaults.object(forKey: "keyboardHeightScale") as? Double ?? 1.0, 0.85), 1.4) }
        set { defaults.set(min(max(newValue, 0.85), 1.4), forKey: "keyboardHeightScale") }
    }

    /// Debug 記錄至 sharedDir/debug.log
    static var debugMode: Bool {
        get { defaults.object(forKey: "debugMode") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "debugMode") }
    }

    /// 詞庫開關 — 極簡版僅萌典詞組，預設開啟
    static func domainEnabled(_ key: String) -> Bool {
        defaults.object(forKey: key) as? Bool ?? (key == "domain_phrases")
    }
    static func setDomainEnabled(_ key: String, _ value: Bool) {
        defaults.set(value, forKey: key)
    }

    static func domainPriority(_ key: String) -> Int {
        defaults.object(forKey: key + "_pri") as? Int ?? 0
    }
}
