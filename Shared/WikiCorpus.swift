import Foundation

/// iOS 極簡語料層：只保留萌典詞組（phrases.bin，PHMM 格式，CC0）。
/// 其餘語料（詞級 n-gram、新聞語料、成語、專業詞典、NER、emoji、地區用詞）不隨附，
/// API 介面與上游 Yabomish 相同（回傳空結果），讓 SuggestionEngine / CandidateRanker 原始碼不需修改。
final class WikiCorpus {
    static let shared = WikiCorpus()

    // 萌典詞組（PHMM: header + sorted UTF-32LE 首字 keys + offsets + counts + phrase blob）
    private var phData: Data?
    private var phKeyCount = 0
    private var phKeysOff = 0
    private var phOffsetsOff = 0
    private var phCountsOff = 0
    private var phPhrasesOff = 0

    static let domainKeys: [(key: String, file: String, label: String)] = [
        ("domain_phrases", "phrases", "萌典詞組"),
    ]
    var domainBinCount: Int { phData != nil ? 1 : 0 }

    init() {
        loadPhrases()
    }

    private func resolvePath(name: String, ext: String) -> String? {
        let shared = AppConstants.sharedDir + "/\(name).\(ext)"
        if FileManager.default.fileExists(atPath: shared) { return shared }
        return Bundle.main.path(forResource: name, ofType: ext)
    }

    private func loadPhrases() {
        guard let p = resolvePath(name: "phrases", ext: "bin") else { return }
        let d: Data
        do { d = try Data(contentsOf: URL(fileURLWithPath: p), options: .mappedIfSafe) }
        catch { DebugLog.log("WikiCorpus loadPhrases: \(error.localizedDescription)"); return }
        guard d.count >= 12, d[0] == 0x50, d[1] == 0x48, d[2] == 0x4D, d[3] == 0x4D else { return }
        phKeyCount = Int(d.u32(4))
        phKeysOff = 8
        phOffsetsOff = phKeysOff + phKeyCount * 4
        phCountsOff = phOffsetsOff + phKeyCount * 4
        phPhrasesOff = phCountsOff + phKeyCount * 2
        guard phPhrasesOff <= d.count else { return }
        phData = d
    }

    func reloadDomains() { loadPhrases() }

    // MARK: - 詞組查詢

    /// 單字 → 該字開頭的完整詞組
    func suggestPhrases(after char: String, limit: Int = 4) -> [String] {
        Array(phraseLookup(char: char, limit: limit))
    }

    /// 多字前綴 → 補全（去除前綴後的餘字），如「馬達」→「加斯加」
    func phraseCompletions(for prefix: String, limit: Int = 3) -> [String] {
        guard prefix.count >= 2, let first = prefix.first else { return [] }
        var results: [String] = []
        for phrase in phraseLookup(char: String(first), limit: 30) {
            if phrase.hasPrefix(prefix) && phrase.count > prefix.count {
                results.append(String(phrase.dropFirst(prefix.count)))
                if results.count >= limit { break }
            }
        }
        return results
    }

    /// 與上游同名：多字前綴補全
    func completions(for prefix: String, limit: Int = 3) -> [String] {
        phraseCompletions(for: prefix, limit: limit)
    }

    private func phraseLookup(char: String, limit: Int = 30) -> [String] {
        guard let d = phData, phKeyCount > 0,
              let s = char.unicodeScalars.first else { return [] }
        let target = s.value
        var lo = 0, hi = phKeyCount - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let k = d.u32(phKeysOff + mid * 4)
            if k == target { return readPhrases(d, at: mid, limit: limit) }
            else if k < target { lo = mid + 1 } else { hi = mid - 1 }
        }
        return []
    }

    private func readPhrases(_ d: Data, at idx: Int, limit: Int) -> [String] {
        var pos = phPhrasesOff + Int(d.u32(phOffsetsOff + idx * 4))
        let count = min(Int(d.u16(phCountsOff + idx * 2)), limit)
        var r: [String] = []
        for _ in 0..<count {
            guard pos >= 0, pos < d.count else { break }
            let len = Int(d[pos]); pos += 1
            guard pos + len * 4 <= d.count else { break }
            var s = ""
            for _ in 0..<len {
                if let sc = Unicode.Scalar(d.u32(pos)) { s.append(Character(sc)) }
                pos += 4
            }
            r.append(s)
        }
        return r
    }

    // MARK: - 上游 API（極簡版由萌典詞組供應或回空）

    /// 詞級語料 — 極簡版一律查萌典
    func suggestWordCorpus(prefix: String, limit: Int = 5) -> [String] {
        phraseCompletions(for: prefix, limit: limit)
    }

    /// 詞庫（第三層）— 極簡版只有萌典；多字前綴回補全餘字
    func suggestAllDomains(prefix: String, limit: Int = 5) -> [String] {
        phraseCompletions(for: prefix, limit: limit)
    }

    /// 單字前綴 → 補全餘字（供 SuggestionEngine 單字 fallback 與 CandidateRanker 使用）
    func suggestDomainTerms(prefix: String, limit: Int = 3) -> [String] {
        guard prefix.count == 1 else { return phraseCompletions(for: prefix, limit: limit) }
        var results: [String] = []
        for phrase in phraseLookup(char: prefix, limit: 30) where phrase.count > 1 {
            results.append(String(phrase.dropFirst()))
            if results.count >= limit { break }
        }
        return results
    }

    // 以下語料極簡版不提供 — 介面保留
    func suggestJingjing(prefix: String, limit: Int = 5) -> [String] { [] }
    func suggestTrigram(prev2: String, prev1: String, limit: Int = 4) -> [String] { [] }
    func suggestChengyu(prefix: String, limit: Int = 3) -> [String] { [] }
    func suggestWordNgram(context: [String], limit: Int = 3) -> [String] { [] }
    func suggestEmoji(for char: String, limit: Int = 2) -> [String] { [] }
    func isRegionDemoted(_ term: String) -> Bool { false }
}

// MARK: - Data helpers（CINTable / BigramSuggest 讀 .bin 用）
// 注意：.bin 索引常是 6-byte stride，offset 不保證對齊 —
// 必須用 loadUnaligned（`load` 在 Debug build 會因對齊 assert 而 crash）。
extension Data {
    func u32(_ off: Int) -> UInt32 {
        guard off >= 0, off + 4 <= count else { return 0 }
        return withUnsafeBytes { $0.loadUnaligned(fromByteOffset: off, as: UInt32.self).littleEndian }
    }
    func u16(_ off: Int) -> UInt16 {
        guard off >= 0, off + 2 <= count else { return 0 }
        return withUnsafeBytes { $0.loadUnaligned(fromByteOffset: off, as: UInt16.self).littleEndian }
    }
}
