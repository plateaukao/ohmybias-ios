import Foundation

/// 同音字查詢：字 → 注音 → 同音字（按字頻排序）。
/// 資料優先走 mmap 二進位（zhuyin_data.bin / pinyin_data.bin / char_freq.bin — v2 格式 ZYM2/PYM2/CFM2，
/// 零 heap、零解析；讀取端 DataMaps.swift，格式見 ohmybias-android tools/gen_data_bins.py），
/// 找不到 .bin 時回退舊版 JSON（使用者 sharedDir 自帶資料的相容路徑）。
final class ZhuyinLookup {
    static let shared = ZhuyinLookup()

    // mmap 二進位
    private var zhuyinBin: ZhuyinTable?
    private var pinyinBin: PinyinTable?
    private var freqBin: CharFreqMap?

    // JSON fallback
    private var charToZhuyins: [String: [String]] = [:]
    private var zhuyinToChars: [String: [String]] = [:]
    private var pinyinToChars: [String: [String]] = [:]
    private var charFreq: [String: Int] = [:]
    private var loaded = false
    init() {}

    private func dataPath(_ name: String, _ ext: String) -> String? {
        let shared = AppConstants.sharedDir + "/\(name).\(ext)"
        if FileManager.default.fileExists(atPath: shared) { return shared }
        return Bundle.main.path(forResource: name, ofType: ext)
    }

    /// 釋放注音/拼音/字頻表 — 只有注音、拼音、同音字模式用得到，離開後或
    /// 記憶體吃緊時可放掉；下次進入該模式 ensureLoaded() 會重新載入。
    /// （mmap 版本身不佔 heap，放掉的是已觸碰的頁面與 JSON fallback 的字典。）
    func release() {
        guard loaded else { return }
        zhuyinBin = nil
        pinyinBin = nil
        freqBin = nil
        charToZhuyins = [:]
        zhuyinToChars = [:]
        pinyinToChars = [:]
        charFreq = [:]
        loaded = false
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        guard MemoryBudget.canAfford(MemoryBudget.zhuyinLookup) else { return }
        if loadBins() {
            loaded = true
            return
        }
        loadJsonFallback()
    }

    private func mapped(_ path: String) -> Data? {
        try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
    }

    /// zhuyin_data.bin（ZYM2）為主；pinyin_data.bin（PYM2，別名指向 ZYM2 音節）與 char_freq.bin（CFM2）各自獨立檔
    private func loadBins() -> Bool {
        guard let zp = dataPath("zhuyin_data", "bin"), let zd = mapped(zp),
              let zt = ZhuyinTable.of(zd) else { return false }
        zhuyinBin = zt
        if let pp = dataPath("pinyin_data", "bin"), let pd = mapped(pp) {
            pinyinBin = PinyinTable.of(pd, zhuyin: zt)
        }
        if let fp = dataPath("char_freq", "bin"), let fd = mapped(fp) {
            freqBin = CharFreqMap.of(fd)
        }
        return true
    }

    private func loadJsonFallback() {
        guard let p = dataPath("zhuyin_data", "json") else {
            return
        }
        let data: Data
        do { data = try Data(contentsOf: URL(fileURLWithPath: p)) }
        catch { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let z2c = json["zhuyin_to_chars"] as? [String: [String]],
              let c2z = json["char_to_zhuyins"] as? [String: [String]] else {
            return
        }
        zhuyinToChars = z2c; charToZhuyins = c2z
        loaded = true
        if let fp = dataPath("char_freq", "json") {
            do {
                let fd = try Data(contentsOf: URL(fileURLWithPath: fp))
                if let freq = (try? JSONSerialization.jsonObject(with: fd)) as? [String: Int] {
                    charFreq = freq
                }
            } catch {}
        }
        if let pp = dataPath("pinyin_data", "json") {
            do {
                let pd = try Data(contentsOf: URL(fileURLWithPath: pp))
                if let pj = try? JSONSerialization.jsonObject(with: pd) as? [String: Any],
                   let p2c = pj["pinyin_to_chars"] as? [String: [String]] { pinyinToChars = p2c }
            } catch {}
        }
    }

    // MARK: - 內部查詢（bin 優先）

    private func freqOf(_ char: String) -> Int {
        if let f = freqBin { return f.get(char) }
        return charFreq[char] ?? 0
    }

    private func zhuyinsOf(_ char: String) -> [String] {
        if let z = zhuyinBin { return z.zhuyinsOf(char) }
        return charToZhuyins[char] ?? []
    }

    private func pinyinLookup(_ key: String) -> [String] {
        if let p = pinyinBin { return p.get(key) }
        return pinyinToChars[key] ?? []
    }

    // MARK: - Sort

    func sortByFreq(_ chars: [String]) -> [String] {
        ensureLoaded()
        return chars.sorted { freqOf($0) > freqOf($1) }
    }

    /// Backward-compat overloads — prevChar no longer used after bigram removal
    func sortByFreq(_ chars: [String], prevChar: String?, curZhuyin: String) -> [String] { sortByFreq(chars) }
    func sortByFreq(_ chars: [String], prevChar: String, curZhuyin: String) -> [String] { sortByFreq(chars) }
    func sortByFreq(_ chars: [String], prevChar: String?) -> [String] { sortByFreq(chars) }

    // MARK: - Lookup

    func lookup(_ char: String) -> [(zhuyin: String, chars: [String])] {
        ensureLoaded()
        let zhuyins = zhuyinsOf(char)
        guard !zhuyins.isEmpty else { return [] }
        // char_to_zhuyins 的順序 = 常用讀音在前，直接保留
        let all = zhuyins.compactMap { zy -> (zhuyin: String, chars: [String])? in
            let raw = charsForZhuyin(zy)
            let filtered = raw.filter { $0 != char }
            guard !filtered.isEmpty else { return nil }
            return (zy, filtered)
        }
        if OhMyBiasPrefs.homophoneMultiReading {
            return all
        }
        guard let best = all.first else { return [] }
        return [best]
    }

    /// Backward-compat overload — prevChar no longer used
    func lookup(_ char: String, prevChar: String?) -> [(zhuyin: String, chars: [String])] { lookup(char) }

    // MARK: - Reverse lookup

    func charsForZhuyin(_ zhuyin: String) -> [String] {
        ensureLoaded()
        if let z = zhuyinBin { return z.charsForZhuyin(zhuyin) }
        return zhuyinToChars[zhuyin] ?? []
    }

    /// Backward-compat overload — prevChar no longer used
    func charsForZhuyin(_ zhuyin: String, prevChar: String?) -> [String] { charsForZhuyin(zhuyin) }

    func charsForPinyin(_ pinyin: String) -> [String] {
        ensureLoaded()
        let direct = pinyinLookup(pinyin)
        if !direct.isEmpty { return direct }
        let converted = pinyin.replacingOccurrences(of: "v", with: "ü")
        if converted != pinyin {
            let c = pinyinLookup(converted)
            if !c.isEmpty { return c }
        }
        return []
    }
}
