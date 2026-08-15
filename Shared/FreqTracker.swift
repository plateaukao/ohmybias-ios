import Foundation
import SQLite3

/// freq.db SQLite 字頻學習＋`,,PIN` 固定排序（含 iCloud merge）。
///
/// 效能（與 Android 版同步的 sweetlime 移植）：freq/bigram/pinned 整份載入記憶體，
/// 每鍵擊的查詢（sorted/sortedWithContext）純走記憶體 — 不再 bgQueue.sync 打 SQLite，
/// 學習也立即可見（舊版查詢看不到未滿批次的 pending）。所有 DB 存取集中在 bgQueue，
/// WAL 照舊。記憶體是即時權威資料、DB 是持久層：decay 兩邊各自套同因子，
/// 下次啟動自 DB 還原。decay 修剪讓表上限約 5000 列/表，記憶體成本無虞。
final class FreqTracker {
    private var db: OpaquePointer?
    private let path: String
    private var recordCount = 0
    private let bgQueue = DispatchQueue(label: "info.plateaukao.ohmybias.freq.bg")
    private var pendingFreq: [(code: String, char: String)] = []
    private var pendingBigram: [(prev: String, char: String)] = []
    private let batchSize = 50

    /// 記憶體快取 — cacheLock 保護（主執行緒讀寫 + bgQueue 載入/重建）
    private var freqCache: [String: [String: Int]] = [:]
    private var bigramCache: [String: [String: Int]] = [:]
    private var pinnedCache: [String: [String]] = [:]
    private let cacheLock = NSLock()
    private let loadGroup = DispatchGroup()

    private var stmtUpsertFreq: OpaquePointer?
    private var stmtUpsertBigram: OpaquePointer?
    private var stmtQueryPinned: OpaquePointer?
    private var stmtUpsertPinned: OpaquePointer?
    private var stmtDeletePinned: OpaquePointer?

    init() {
        // SQLite DB always in the App Group container (never in iCloud —
        // WAL mode is incompatible with cloud sync)
        let dir = AppConstants.sharedDir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        self.path = dir + "/freq.db"
        // 開檔/遷移/整份載入都在 bgQueue — 不佔鍵盤啟動主執行緒
        loadGroup.enter()
        bgQueue.async { [self] in
            openDB()
            migrateFromJSON(dir: dir)
            loadCaches()
            loadGroup.leave()
        }
    }

    deinit {
        sqlite3_finalize(stmtUpsertFreq)
        sqlite3_finalize(stmtUpsertBigram)
        sqlite3_finalize(stmtQueryPinned)
        sqlite3_finalize(stmtUpsertPinned)
        sqlite3_finalize(stmtDeletePinned)
        sqlite3_close(db)
    }

    /// 首次查詢若早於載入完成則短暫等待（實務上載入遠快於第一個按鍵）
    private func awaitLoad() {
        _ = loadGroup.wait(timeout: .now() + .milliseconds(500))
    }

    // MARK: - DB Setup（bgQueue 專用）

    private func openDB() {
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            DebugLog.log("FreqTracker sqlite3_open failed: \(path)")
            return
        }
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA synchronous=NORMAL")
        exec("CREATE TABLE IF NOT EXISTS freq(code TEXT, char TEXT, n INTEGER, PRIMARY KEY(code,char))")
        exec("CREATE TABLE IF NOT EXISTS bigram(prev TEXT, char TEXT, n INTEGER, PRIMARY KEY(prev,char))")
        exec("CREATE TABLE IF NOT EXISTS pinned(code TEXT PRIMARY KEY, chars TEXT NOT NULL)")
        // 預設固定排序（常見同碼字衝突）
        exec("INSERT OR IGNORE INTO pinned(code,chars) VALUES('hj','手乎')")
        prepare("INSERT INTO freq(code,char,n) VALUES(?1,?2,1) ON CONFLICT(code,char) DO UPDATE SET n=n+1", &stmtUpsertFreq)
        prepare("INSERT INTO bigram(prev,char,n) VALUES(?1,?2,1) ON CONFLICT(prev,char) DO UPDATE SET n=n+1", &stmtUpsertBigram)
        prepare("SELECT chars FROM pinned WHERE code=?1", &stmtQueryPinned)
        prepare("INSERT OR REPLACE INTO pinned(code,chars) VALUES(?1,?2)", &stmtUpsertPinned)
        prepare("DELETE FROM pinned WHERE code=?1", &stmtDeletePinned)
    }

    /// bgQueue 專用：三表整份讀進記憶體。
    /// 記憶體此刻只含載入前的即時紀錄（同時也在 pending 排隊）— 疊加 DB 計數即為完整狀態。
    private func loadCaches() {
        let f = readCounts("SELECT code,char,n FROM freq")
        let b = readCounts("SELECT prev,char,n FROM bigram")
        var p: [String: [String]] = [:]
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT code, chars FROM pinned", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let code = String(cString: sqlite3_column_text(stmt, 0))
                let chars = String(cString: sqlite3_column_text(stmt, 1))
                p[code] = Array(chars).map(String.init)
            }
        }
        sqlite3_finalize(stmt)
        cacheLock.lock()
        for (key, m) in f { for (ch, n) in m { freqCache[key, default: [:]][ch, default: 0] += n } }
        for (key, m) in b { for (ch, n) in m { bigramCache[key, default: [:]][ch, default: 0] += n } }
        for (k, v) in p where pinnedCache[k] == nil { pinnedCache[k] = v }
        cacheLock.unlock()
    }

    /// bgQueue 專用
    private func readCounts(_ sql: String) -> [String: [String: Int]] {
        var r: [String: [String: Int]] = [:]
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return r }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let key = String(cString: sqlite3_column_text(stmt, 0))
            let ch = String(cString: sqlite3_column_text(stmt, 1))
            r[key, default: [:]][ch] = Int(sqlite3_column_int(stmt, 2))
        }
        sqlite3_finalize(stmt)
        return r
    }

    // MARK: - Record（記憶體即時更新，DB 批次寫入丟 bgQueue）

    func record(code: String, char: String) {
        var freqRows: [(code: String, char: String)]?
        var bigramRows: [(prev: String, char: String)]?
        var doDecay = false
        cacheLock.lock()
        freqCache[code, default: [:]][char, default: 0] += 1
        pendingFreq.append((code, char))
        recordCount += 1
        if pendingFreq.count >= batchSize {
            freqRows = pendingFreq
            pendingFreq.removeAll(keepingCapacity: true)
        }
        if recordCount >= 500 {
            recordCount = 0
            doDecay = true
            decayMemoryLocked(0.9)
            // decay 前先送出剩餘 pending — DB 端「先加後衰減」與記憶體一致
            if !pendingFreq.isEmpty { freqRows = (freqRows ?? []) + pendingFreq; pendingFreq.removeAll(keepingCapacity: true) }
            if !pendingBigram.isEmpty { bigramRows = pendingBigram; pendingBigram.removeAll(keepingCapacity: true) }
        }
        cacheLock.unlock()
        if freqRows != nil || bigramRows != nil || doDecay {
            bgQueue.async { [self] in
                if let rows = freqRows { flushRows(rows.map { ($0.code, $0.char) }, stmtUpsertFreq) }
                if let rows = bigramRows { flushRows(rows.map { ($0.prev, $0.char) }, stmtUpsertBigram) }
                if doDecay { decayDB(0.9) }
            }
        }
    }

    func recordBigram(prev: String, char: String) {
        guard !prev.isEmpty else { return }
        var rows: [(prev: String, char: String)]?
        cacheLock.lock()
        bigramCache[prev, default: [:]][char, default: 0] += 1
        pendingBigram.append((prev, char))
        if pendingBigram.count >= batchSize {
            rows = pendingBigram
            pendingBigram.removeAll(keepingCapacity: true)
        }
        cacheLock.unlock()
        if let rows {
            bgQueue.async { [self] in flushRows(rows.map { ($0.prev, $0.char) }, stmtUpsertBigram) }
        }
    }

    func recordTrigram(prev2: String, prev1: String, char: String) {
        guard !prev2.isEmpty, !prev1.isEmpty else { return }
        recordBigram(prev: prev2 + "|" + prev1, char: char)
    }

    /// bgQueue 專用
    private func flushRows(_ rows: [(String, String)], _ stmt: OpaquePointer?) {
        guard !rows.isEmpty else { return }
        exec("BEGIN")
        for (key, char) in rows { bindAndStep(stmt, key, char) }
        exec("COMMIT")
    }

    /// 送出所有未寫入紀錄並等待完成 — 鍵盤收起/extension 結束前呼叫，保住學習資料
    func flushAll() {
        cacheLock.lock()
        let f = pendingFreq; pendingFreq.removeAll(keepingCapacity: true)
        let b = pendingBigram; pendingBigram.removeAll(keepingCapacity: true)
        cacheLock.unlock()
        // 即使 pending 為空也要 sync 一次 — 排入 bgQueue 但尚未執行的批次寫入得以排空
        bgQueue.sync { [self] in
            flushRows(f.map { ($0.code, $0.char) }, stmtUpsertFreq)
            flushRows(b.map { ($0.prev, $0.char) }, stmtUpsertBigram)
        }
    }

    // MARK: - Query（純記憶體 — 每鍵擊皆呼叫，不碰 SQLite）

    private func memFreq(_ code: String) -> [String: Int] {
        awaitLoad()
        cacheLock.lock(); defer { cacheLock.unlock() }
        return freqCache[code] ?? [:]
    }

    private func memBigram(_ prev: String) -> [String: Int] {
        awaitLoad()
        cacheLock.lock(); defer { cacheLock.unlock() }
        return bigramCache[prev] ?? [:]
    }

    func sorted(_ candidates: [String], forCode code: String) -> [String] {
        if code.hasPrefix(",") { return candidates }
        let pinned = pinnedChars(forCode: code)
        let counts = memFreq(code)
        var result: [String]
        if !counts.isEmpty {
            result = candidates.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
        } else {
            result = candidates
        }
        guard let pinned, !pinned.isEmpty else { return result }
        let pinSet = Set(pinned)
        let rest = result.filter { !pinSet.contains($0) }
        let front = pinned.filter { result.contains($0) }
        return front + rest
    }

    func sortedWithContext(_ candidates: [String], forCode code: String, prev: String) -> [String] {
        if code.hasPrefix(",") { return candidates }
        guard !prev.isEmpty else { return sorted(candidates, forCode: code) }
        let pinned = pinnedChars(forCode: code)
        let uni = memFreq(code)
        let bi = memBigram(prev)
        var result: [String]
        if uni.isEmpty && bi.isEmpty {
            result = candidates
        } else {
            let uniT = max(1.0, Double(uni.values.reduce(0, +)))
            let biT = max(1.0, Double(bi.values.reduce(0, +)))
            let biCount = bi.count
            let total = biCount + candidates.count
            let alpha: Double = total < 100 ? 0.4 : Double(candidates.count) / Double(total)
            var scores: [String: Double] = [:]
            for c in candidates {
                if let b = bi[c] {
                    scores[c] = Double(b) / biT
                } else {
                    scores[c] = alpha * Double(uni[c] ?? 0) / uniT
                }
            }
            result = candidates.sorted { (scores[$0] ?? 0) > (scores[$1] ?? 0) }
        }
        guard let pinned, !pinned.isEmpty else { return result }
        let pinSet = Set(pinned)
        let rest = result.filter { !pinSet.contains($0) }
        let front = pinned.filter { result.contains($0) }
        return front + rest
    }

    /// Top N learned bigram suggestions for a given prev char
    func topBigrams(prev: String, limit: Int = 3) -> [String] {
        guard !prev.isEmpty else { return [] }
        let counts = memBigram(prev)
        guard !counts.isEmpty else { return [] }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map { $0.key }
    }

    /// Reorder suggestion candidates by bigram frequency (learned from user selections)
    /// Stable: only moves candidates with recorded bigram to front; rest keep original order.
    func bigramBoost(prev: String, candidates: [String]) -> [String] {
        guard !prev.isEmpty else { return candidates }
        let counts = memBigram(prev)
        guard !counts.isEmpty else { return candidates }
        var boosted = candidates.filter { counts[$0] != nil }.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
        let rest = candidates.filter { counts[$0] == nil }
        boosted.append(contentsOf: rest)
        return boosted
    }

    // MARK: - Pinned order

    /// Reload pinned cache from DB (called when prefs change from external app).
    func reloadPinned() {
        bgQueue.async { [self] in
            var p: [String: [String]] = [:]
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT code, chars FROM pinned", -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let code = String(cString: sqlite3_column_text(stmt, 0))
                    let chars = String(cString: sqlite3_column_text(stmt, 1))
                    p[code] = Array(chars).map(String.init)
                }
            }
            sqlite3_finalize(stmt)
            cacheLock.lock()
            pinnedCache = p
            cacheLock.unlock()
        }
    }

    /// Set pinned order for a code. chars is the ordered list of characters.
    func pin(code: String, chars: [String]) {
        cacheLock.lock()
        pinnedCache[code] = chars
        cacheLock.unlock()
        let joined = chars.joined()
        bgQueue.async { [self] in
            guard let stmt = stmtUpsertPinned else { return }
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, code, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, joined, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
    }

    /// Remove pinned order for a code.
    func unpin(code: String) {
        cacheLock.lock()
        pinnedCache.removeValue(forKey: code)
        cacheLock.unlock()
        bgQueue.async { [self] in
            guard let stmt = stmtDeletePinned else { return }
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, code, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
    }

    /// Get pinned chars for a code (from cache).
    func pinnedChars(forCode code: String) -> [String]? {
        awaitLoad()
        cacheLock.lock(); defer { cacheLock.unlock() }
        return pinnedCache[code]
    }

    // MARK: - Maintenance

    /// cacheLock 持有中呼叫
    private func decayMemoryLocked(_ factor: Double) {
        for (key, m) in freqCache {
            for (ch, v) in m { freqCache[key]![ch] = max(1, Int(Double(v) * factor)) }
        }
        for (key, m) in bigramCache {
            for (ch, v) in m { bigramCache[key]![ch] = max(1, Int(Double(v) * factor)) }
        }
    }

    /// bgQueue 專用 — 記憶體端已同步套過同因子；此處僅維護持久層並修剪表大小
    private func decayDB(_ factor: Double) {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE freq SET n=MAX(1,CAST(n*?1 AS INTEGER))", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, factor)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        exec("DELETE FROM freq WHERE n<1")
        // Prune entries that have decayed to minimum (n=1) to prevent unbounded growth
        exec("DELETE FROM freq WHERE n<=1 AND rowid NOT IN (SELECT rowid FROM freq ORDER BY n DESC LIMIT 5000)")
        if sqlite3_prepare_v2(db, "UPDATE bigram SET n=MAX(1,CAST(n*?1 AS INTEGER))", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, factor)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        exec("DELETE FROM bigram WHERE n<1")
        exec("DELETE FROM bigram WHERE n<=1 AND rowid NOT IN (SELECT rowid FROM bigram ORDER BY n DESC LIMIT 5000)")
    }

    func decay(factor: Double = 0.9) {
        var f: [(code: String, char: String)] = []
        var b: [(prev: String, char: String)] = []
        cacheLock.lock()
        decayMemoryLocked(factor)
        f = pendingFreq; pendingFreq.removeAll(keepingCapacity: true)
        b = pendingBigram; pendingBigram.removeAll(keepingCapacity: true)
        cacheLock.unlock()
        bgQueue.async { [self] in
            flushRows(f.map { ($0.code, $0.char) }, stmtUpsertFreq)
            flushRows(b.map { ($0.prev, $0.char) }, stmtUpsertBigram)
            decayDB(factor)
        }
    }

    func reset() {
        cacheLock.lock()
        pendingFreq.removeAll()
        pendingBigram.removeAll()
        freqCache.removeAll()
        bigramCache.removeAll()
        recordCount = 0
        cacheLock.unlock()
        bgQueue.async { [self] in
            exec("DELETE FROM freq")
            exec("DELETE FROM bigram")
        }
    }

    func saveIfNeeded() {
        // SQLite WAL auto-flushes; kept for API compat
    }

    func deferredMerge() {
        bgQueue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard MemoryBudget.canAfford(5) else { return }
            self?.mergeFromiCloud()
        }
    }

    // MARK: - Migration from JSON

    private struct JSONStorage: Codable {
        let freq: [String: [String: Int]]
        let bigram: [String: [String: Int]]?
    }

    /// bgQueue 專用（init 載入前執行 — 匯入結果由後續 loadCaches 帶進記憶體）
    private func migrateFromJSON(dir: String) {
        let jsonPath = dir + "/freq.json"
        guard FileManager.default.fileExists(atPath: jsonPath) else { return }
        let data: Data
        do { data = try Data(contentsOf: URL(fileURLWithPath: jsonPath)) }
        catch { DebugLog.log("FreqTracker migrateFromJSON read: \(error.localizedDescription)"); return }
        // Backup first
        let backup = dir + "/freq.json.bak"
        if !FileManager.default.fileExists(atPath: backup) {
            try? FileManager.default.copyItem(atPath: jsonPath, toPath: backup)
        }
        do {
            let s = try JSONDecoder().decode(JSONStorage.self, from: data)
            importJSON(s)
            try? FileManager.default.removeItem(atPath: jsonPath)
        } catch {
            do {
                let legacyFreq = try JSONDecoder().decode([String: [String: Int]].self, from: data)
                importJSON(JSONStorage(freq: legacyFreq, bigram: nil))
                try? FileManager.default.removeItem(atPath: jsonPath)
            } catch { DebugLog.log("FreqTracker migrateFromJSON decode: \(error.localizedDescription)") }
        }
    }

    /// bgQueue 專用
    private func importJSON(_ s: JSONStorage) {
        exec("BEGIN")
        for (code, counts) in s.freq {
            for (char, n) in counts { upsertMax("freq", code, char, n) }
        }
        if let bg = s.bigram {
            for (prev, counts) in bg {
                for (char, n) in counts { upsertMax("bigram", prev, char, n) }
            }
        }
        exec("COMMIT")
    }

    private func upsertMax(_ table: String, _ key: String, _ char: String, _ n: Int) {
        let col1 = table == "bigram" ? "prev" : "code"
        let sql = "INSERT INTO \(table)(\(col1),char,n) VALUES(?1,?2,?3) ON CONFLICT(\(col1),char) DO UPDATE SET n=MAX(n,?3)"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, char, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, Int32(n))
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    // MARK: - iCloud Sync

    private static var iCloudFreqURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents/freq.json")
    }

    /// bgQueue 專用
    private func mergeFromiCloud() {
        guard let url = Self.iCloudFreqURL else { return }
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { DebugLog.log("FreqTracker mergeFromiCloud read: \(error.localizedDescription)"); return }
        do {
            let remote = try JSONDecoder().decode(JSONStorage.self, from: data)
            importJSON(remote)
            resyncCachesFromDB()
        }
        catch { DebugLog.log("FreqTracker mergeFromiCloud decode: \(error.localizedDescription)") }
    }

    /// bgQueue 專用：pending 先落盤 → DB 整份重讀 → 換掉記憶體（iCloud merge 後同步）
    private func resyncCachesFromDB() {
        cacheLock.lock()
        let f = pendingFreq; pendingFreq.removeAll(keepingCapacity: true)
        let b = pendingBigram; pendingBigram.removeAll(keepingCapacity: true)
        cacheLock.unlock()
        flushRows(f.map { ($0.code, $0.char) }, stmtUpsertFreq)
        flushRows(b.map { ($0.prev, $0.char) }, stmtUpsertBigram)
        let nf = readCounts("SELECT code,char,n FROM freq")
        let nb = readCounts("SELECT prev,char,n FROM bigram")
        cacheLock.lock()
        freqCache = nf
        bigramCache = nb
        cacheLock.unlock()
    }

    // MARK: - SQLite Helpers

    private func exec(_ sql: String) { sqlite3_exec(db, sql, nil, nil, nil) }
    private func prepare(_ sql: String, _ stmt: inout OpaquePointer?) { sqlite3_prepare_v2(db, sql, -1, &stmt, nil) }

    private func bindAndStep(_ stmt: OpaquePointer?, _ key: String, _ char: String) {
        guard let stmt else { return }
        sqlite3_reset(stmt)
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, char, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
