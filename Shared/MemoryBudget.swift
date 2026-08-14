import Foundation

/// Memory budget manager — iOS 鍵盤 extension 約 60MB 上限，預算 40MB。
enum MemoryBudget {
    // MARK: - Budget allocation (MB)
    static let total: Int = 40

    static let cinTable: Int = 10       // table dict + trie + cache parse
    static let freqTracker: Int = 2     // SQLite + prepared statements
    static let phrasesBin: Int = 1      // mmap phrases.bin
    static let zhuyinLookup: Int = 4    // JSON dicts (lazy)
    static let reverseTable: Int = 4    // CINTable reverse lookup (lazy)
    static let uiOverhead: Int = 3      // CandidateBar, KeyboardView, haptics
    static let collectionPanel: Int = 1 // 符號/emoji/顏文字面板（CollectionData 靜態表＋UICollectionView）

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
        guard currentMB > 65 else { return }
        cinTable.releaseOptionalCaches()
    }
}
