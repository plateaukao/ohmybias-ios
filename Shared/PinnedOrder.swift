import Foundation

/// `,,PIN` 固定排序 — 碼 → 使用者指定的同碼字順序（`,,UNPIN碼` 解除）。
/// 純文字檔 `pinned.txt` 一行一碼：`碼<TAB>字<TAB>字…`（一字一欄，非 BMP 字不必另行編碼），
/// 與 Android 版格式相同、檔案可互通。條目通常只有幾筆，啟動整份讀進小字典即可。
/// 取代原本 freq.db 的 pinned 表 — 字頻學習已移除，固定排序是唯一保留的候選重排。
final class PinnedOrder {
    static let shared = PinnedOrder()
    static let fileName = "pinned.txt"
    /// 沒有檔案時的內建預設（常見同碼字衝突）
    static let defaults: [String: [String]] = ["hj": ["手", "乎"]]

    private let path: String
    private var table: [String: [String]] = [:]

    init(path: String? = nil) {
        self.path = path ?? AppConstants.sharedDir + "/" + Self.fileName
        if let data = FileManager.default.contents(atPath: path ?? self.path),
           let s = String(data: data, encoding: .utf8) {
            table = Self.parse(s)
        } else {
            table = Self.defaults
        }
    }

    static func parse(_ content: String) -> [String: [String]] {
        var t: [String: [String]] = [:]
        for line in content.split(separator: "\n") {
            let fields = line.split(separator: "\t").map { String($0).trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 2, !fields[0].isEmpty else { continue }
            let chars = fields[1...].filter { !$0.isEmpty }
            if !chars.isEmpty { t[fields[0].lowercased()] = Array(chars) }
        }
        return t
    }

    static func serialize(_ t: [String: [String]]) -> String {
        t.keys.sorted().map { ([$0] + (t[$0] ?? [])).joined(separator: "\t") + "\n" }.joined()
    }

    private func save() {
        try? Self.serialize(table).write(toFile: path, atomically: true, encoding: .utf8)
    }

    func chars(forCode code: String) -> [String]? { table[code.lowercased()] }

    func pin(code: String, chars: [String]) {
        table[code.lowercased()] = chars
        save()
    }

    func unpin(code: String) {
        table.removeValue(forKey: code.lowercased())
        save()
    }

    /// 固定的字依指定順序排前面，其餘維持原序；不增減候選
    func apply(_ candidates: [String], forCode code: String) -> [String] {
        guard let pinned = table[code.lowercased()], !pinned.isEmpty else { return candidates }
        let pinSet = Set(pinned)
        return pinned.filter { candidates.contains($0) } + candidates.filter { !pinSet.contains($0) }
    }
}
