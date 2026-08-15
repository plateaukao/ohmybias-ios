import Foundation

/// 表情面板「常用」分類 — 最近使用的 emoji，MRU 順序（最新在前），上限 40。
/// 存 recent_emojis.txt 一行一個；記錄先改記憶體、寫檔丟背景 queue（點按路徑零 I/O）。
/// 與 Android 版 keyboard/RecentEmojis.kt 一對一。
final class RecentEmojis {
    static let shared = RecentEmojis()
    private static let maxCount = 40
    private let writeQueue = DispatchQueue(label: "ohmybias-recent", qos: .utility)

    private var items: [String] = []
    private var loaded = false

    private var path: String { AppConstants.sharedDir + "/recent_emojis.txt" }

    func all() -> [String] {
        loadIfNeeded()
        return items
    }

    func record(_ emoji: String) {
        loadIfNeeded()
        items.removeAll { $0 == emoji }
        items.insert(emoji, at: 0)
        if items.count > Self.maxCount { items.removeLast(items.count - Self.maxCount) }
        let snapshot = items.joined(separator: "\n")
        let p = path
        writeQueue.async {
            try? snapshot.write(toFile: p, atomically: true, encoding: .utf8)
        }
    }

    private func loadIfNeeded() {
        if loaded { return }
        loaded = true
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return }
        for line in content.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if !s.isEmpty && items.count < Self.maxCount { items.append(s) }
        }
    }
}
