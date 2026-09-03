import Foundation

/// Memory budget manager — iOS 鍵盤 extension 的 dirty memory 上限由系統決定（機型／iOS 版本
/// 不同），這裡以 `os_proc_available_memory()` 現場量「離上限還剩多少」，不再寫死一個數字。
/// 拿不到（模擬器沒有上限、macOS 測試）時退回 `assumedLimitMB`。
enum MemoryBudget {
    // MARK: - Budget allocation (MB)
    static let total: Int = 40

    static let cinTable: Int = 10       // table dict + trie + cache parse
    static let phrasesBin: Int = 1      // mmap phrases.bin
    static let zhuyinLookup: Int = 1    // mmap zhuyin/pinyin/char_freq .bin（lazy；JSON fallback 才會吃到 ~4MB）
    static let reverseTable: Int = 4    // CINTable reverse lookup (lazy)
    static let uiOverhead: Int = 3      // CandidateBar, KeyboardView, haptics
    static let collectionPanel: Int = 1 // 符號/emoji/顏文字面板（CollectionData 靜態表＋UICollectionView）
    static let settingsPanel: Int = 10  // ⚙ 設定面板 — 首次載入 SwiftUI runtime（實測約 10MB）

    /// 量不到真實上限時的假設值（舊版寫死的門檻；實機 jetsam 觀察約 77MB、警告約 55MB）
    static let assumedLimitMB: Int = 75
    /// 剩餘空間低於此值視為危急 — 記憶體警告時只有到這程度才拆使用者正在看的面板
    static let criticalHeadroomMB: Int = 10
    /// 收鍵盤時剩餘空間低於此值就順手釋放可選快取（等同舊版 footprint > 55MB）
    static let trimHeadroomMB: Int = 20
    /// 逛 emoji 面板時 footprint 到此即清 CoreText 字形快取 — 離上限 30MB（舊版寫死 45）
    static var glyphCacheDrainMB: Int { limitMB - 30 }

    // MARK: - Runtime measurement

    /// phys_footprint（jetsam 看的就是這個）
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

    /// 系統回報的「離 dirty memory 上限還剩多少」— 沒有上限（模擬器）或非 iOS 時為 nil。
    /// 回 0 代表「不是 app」或已超限；超過 4GB 視為沒設上限。
    static var availableMB: Int? {
        #if os(iOS)
        let bytes = os_proc_available_memory()
        guard bytes > 0, bytes < 4_096 * 1_048_576 else { return nil }
        return Int(bytes / 1_048_576)
        #else
        return nil
        #endif
    }

    /// 這台機器對本行程的實際上限（量得到就用系統值，否則用假設值）
    static var limitMB: Int {
        if let avail = availableMB { return currentMB + avail }
        return assumedLimitMB
    }

    /// 離上限還剩多少（量不到就用假設值推算）
    static var headroomMB: Int {
        availableMB ?? (assumedLimitMB - currentMB)
    }

    /// 給 toast／診斷用：「52 / 77 MB」
    static var summary: String { "\(currentMB) / \(limitMB) MB" }

    /// Override for tests — set to true to bypass memory checks.
    static var bypassChecks = false

    /// Returns true if we have enough headroom to load an optional feature.
    static func canAfford(_ mb: Int) -> Bool {
        bypassChecks || headroomMB > mb
    }

    /// 剩餘空間已到危急線（記憶體警告時決定要不要拆面板）
    static var isCritical: Bool { !bypassChecks && headroomMB < criticalHeadroomMB }

    // MARK: - Relief

    /// 鍵盤層額外的釋放動作（CoreText 字形快取等 Shared 看不到的東西）— 由 controller 註冊
    static var extraRelief: (() -> Void)?

    /// 想載一個可選功能但空間不夠時呼叫：先把所有可重建的快取放掉，再看夠不夠。
    /// 回 false 才真的拒絕 — 拒絕是最後手段，不是第一反應。
    static func makeRoom(for mb: Int, cinTable: CINTable) -> Bool {
        if canAfford(mb) { return true }
        releaseAll(cinTable: cinTable)
        return canAfford(mb)
    }

    /// Call this when memory is tight — release optional caches.
    static func trimIfNeeded(cinTable: CINTable) {
        guard headroomMB < trimHeadroomMB else { return }
        releaseAll(cinTable: cinTable)
    }

    /// 無條件釋放所有可重建的快取（記憶體警告時用 — 此時沒有猶豫的餘地）
    static func releaseAll(cinTable: CINTable) {
        cinTable.releaseOptionalCaches()
        ZhuyinLookup.shared.release()
        extraRelief?()
        // Swift free 不會把頁面還給 OS — 明確要 malloc 交回，jetsam 看的是 phys_footprint
        malloc_zone_pressure_relief(nil, 0)
    }
}
