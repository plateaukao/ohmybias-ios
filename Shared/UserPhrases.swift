import Foundation

/// 使用者常用語（♥ 面板內容＋聯想自訂詞＋自訂組字碼捷徑）。
/// 純文字檔 `user_phrases.txt` 一行一詞：`詞` 或 `詞<TAB>組字碼`。
/// 有組字碼的詞可直接用鍵盤打碼叫出，不必開 ♥ 面板（見 `CINTable.shortcutLookup`）。
/// 格式與 Android 版相同，檔案可互通。
final class UserPhrases {
    static let shared = UserPhrases()

    static let fileName = "user_phrases.txt"
    static var filePath: String { AppConstants.sharedDir + "/" + fileName }

    /// 一筆常用語；`code` 為自訂組字碼（nil = 只在面板／聯想出現）
    struct Entry: Equatable {
        var phrase: String
        var code: String?
        init(_ phrase: String, _ code: String? = nil) { self.phrase = phrase; self.code = code }
    }

    /// 組字碼允許的字元 — 字母頁打得出來的鍵（嘸蝦米碼本身只用這些）
    private static let codeChars: Set<Character> = Set("abcdefghijklmnopqrstuvwxyz,.'[]")

    /// 組字碼是否合法（只含允許字元、非空、不以 ,, 開頭 — 那是指令前綴）
    static func isValidCode(_ code: String) -> Bool {
        !code.isEmpty && code.allSatisfy { codeChars.contains($0) } && !code.hasPrefix(",,")
    }

    /// 解析檔案內容 — 空行跳過；單字（長度 < 2）一樣保留為常用語，
    /// 但不進聯想表（聯想要「首字＋餘字」才有意義）
    static func parse(_ content: String) -> [Entry] {
        var out: [Entry] = []
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            let phrase = parts[0].trimmingCharacters(in: .whitespaces)
            if phrase.isEmpty { continue }
            var code: String? = nil
            if parts.count > 1 {
                let c = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
                if isValidCode(c) { code = c }
            }
            out.append(Entry(phrase, code))
        }
        return out
    }

    static func serialize(_ entries: [Entry]) -> String {
        var s = ""
        for e in entries where !e.phrase.isEmpty {
            s += e.phrase
            if let c = e.code { s += "\t" + c }
            s += "\n"
        }
        return s
    }

    private(set) var entries: [Entry] = []
    private var table: [Character: [String]] = [:]
    /// 組字碼 → 常用語（一碼可對多詞，依檔案順序）
    private(set) var shortcuts: [String: [String]] = [:]

    /// 上次讀檔時的修改時間 — 鍵盤 extension 行程可能活過容器 app 的編輯，據此偵測變更
    private var loadedFileDate: Date?

    private init() { reload() }

    private static func fileModificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: filePath))?[.modificationDate] as? Date
    }

    func reload() {
        loadedFileDate = Self.fileModificationDate()
        var content = ""
        if let data = FileManager.default.contents(atPath: Self.filePath),
           let s = String(data: data, encoding: .utf8) { content = s }
        apply(Self.parse(content))
    }

    /// 檔案修改時間跟上次讀的不同才重讀；回傳是否真的重讀了
    @discardableResult
    func reloadIfChanged() -> Bool {
        if Self.fileModificationDate() == loadedFileDate { return false }
        reload()
        return true
    }

    /// 寫檔並立即生效（設定頁儲存用）
    func save(_ entries: [Entry]) {
        try? Self.serialize(entries).write(toFile: Self.filePath, atomically: true, encoding: .utf8)
        loadedFileDate = Self.fileModificationDate()
        apply(entries)
    }

    private func apply(_ entries: [Entry]) {
        var m: [Character: [String]] = [:]
        var sc: [String: [String]] = [:]
        for e in entries {
            if e.phrase.count >= 2, let first = e.phrase.first { m[first, default: []].append(e.phrase) }
            if let c = e.code { sc[c, default: []].append(e.phrase) }
        }
        self.entries = entries
        table = m
        shortcuts = sc
    }

    /// Return phrases starting with `char`, returning the remainder (excluding first char)
    func suggest(after char: String, limit: Int = 3) -> [String] {
        guard let ch = char.first, let phrases = table[ch] else { return [] }
        return phrases.prefix(limit).map { String($0.dropFirst()) }
    }

    /// 全部常用語（供 ♥ 面板列出）
    func allPhrases() -> [String] {
        entries.map { $0.phrase }.sorted()
    }

    /// Return full phrases starting with `prefix`
    func completions(for prefix: String, limit: Int = 3) -> [String] {
        guard let first = prefix.first, let phrases = table[first] else { return [] }
        return phrases.filter { $0.hasPrefix(prefix) && $0.count > prefix.count }.prefix(limit).map { String($0) }
    }
}
