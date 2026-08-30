import Foundation

/// Memory budget manager — iOS 鍵盤 extension 約 60MB 上限，預算 40MB。
enum MemoryBudget {
    // MARK: - Budget allocation (MB)
    static let total: Int = 40

    static let cinTable: Int = 10       // table dict + trie + cache parse
    static let freqTracker: Int = 2     // SQLite + prepared statements
    static let phrasesBin: Int = 1      // mmap phrases.bin
    static let zhuyinLookup: Int = 1    // mmap zhuyin/pinyin/char_freq .bin（lazy；JSON fallback 才會吃到 ~4MB）
    static let reverseTable: Int = 4    // CINTable reverse lookup (lazy)
    static let uiOverhead: Int = 3      // CandidateBar, KeyboardView, haptics
    static let collectionPanel: Int = 1 // 符號/emoji/顏文字面板（CollectionData 靜態表＋UICollectionView）
    static let settingsPanel: Int = 10  // ⚙ 設定面板 — 首次載入 SwiftUI runtime（實測約 10MB）
    static let glyphCacheDrainMB: Int = 45  // 逛 emoji 面板時 footprint 到此即清 CoreText 字形快取（警告約 55MB、jetsam 約 77MB）

    // MARK: - Runtime check

    static var currentMB: Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return r == KERN_SUCCESS ? Int(info.phys_footprint) / 1_048_576 : 0
    }

    /// Override for tests — set to true to bypass memory checks.
    static var bypassChecks = false

    /// Returns true if we have enough headroom to load an optional feature.
    static func canAfford(_ mb: Int) -> Bool {
        bypassChecks || currentMB + mb < 75
    }

    /// Call this when memory is tight — release optional caches.
    static func trimIfNeeded(cinTable: CINTable) {
        guard currentMB > 55 else { return }
        releaseAll(cinTable: cinTable)
    }

    /// 無條件釋放所有可重建的快取（記憶體警告時用 — 此時沒有猶豫的餘地）
    static func releaseAll(cinTable: CINTable) {
        cinTable.releaseOptionalCaches()
        ZhuyinLookup.shared.release()
    }
}
