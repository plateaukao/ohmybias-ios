import Foundation

/// v2 資料表讀取器（ZYM2 / PYM2 / CFM2）— 與 Android `shared/DataMaps.kt` 一對一。
/// 全部 mmap、零 heap、鍵表可二進位搜尋；格式與省法見 ohmybias-android `tools/gen_data_bins.py` 檔頭。

/// CPKT：codepoint 鍵表。BMP 段以 32 筆為區塊（區塊首鍵絕對值 u16 + 區塊內 u16 差值），
/// 非 BMP 段為排序 u32。回傳鍵的索引（BMP 段 0..nb−1，非 BMP 段接續），查無回 −1。
struct CodepointKeys {
    static let block = 32

    private let d: Data
    let count: Int
    private let bmpCount: Int
    private let headCount: Int
    private let headsOff: Int
    private let deltasOff: Int
    private let extOff: Int

    init(_ d: Data, count: Int, bmpCount: Int, headsOff: Int) {
        self.d = d
        self.count = count
        self.bmpCount = bmpCount
        headCount = (bmpCount + CodepointKeys.block - 1) / CodepointKeys.block
        self.headsOff = headsOff
        deltasOff = headsOff + 2 * headCount
        extOff = deltasOff + 2 * bmpCount
    }

    /// 三段合計位元組數（接在後面的區塊由此算起點）
    var byteSize: Int { 2 * headCount + 2 * bmpCount + 4 * (count - bmpCount) }

    func indexOf(_ cp: UInt32) -> Int {
        if cp > 0xFFFF {
            var lo = 0, hi = count - bmpCount - 1
            while lo <= hi {
                let mid = (lo + hi) / 2
                let k = d.u32(extOff + 4 * mid)
                if k == cp { return bmpCount + mid }
                if k < cp { lo = mid + 1 } else { hi = mid - 1 }
            }
            return -1
        }
        guard headCount > 0 else { return -1 }
        let target = Int(cp)
        // 最後一個首鍵 ≤ cp 的區塊
        var lo = 0, hi = headCount - 1, blk = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if Int(d.u16(headsOff + 2 * mid)) <= target { blk = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        guard blk >= 0 else { return -1 }
        var i = blk * CodepointKeys.block
        var k = Int(d.u16(headsOff + 2 * blk))
        if k == target { return i }
        let end = min(i + CodepointKeys.block, bmpCount)
        i += 1
        while i < end {
            k += Int(d.u16(deltasOff + 2 * i))
            if k == target { return i }
            if k > target { return -1 }
            i += 1
        }
        return -1
    }
}

/// ZYM2：注音音節 → 字（UTF-16 code unit 表）＋ 字 → 音節索引（反查）。
final class ZhuyinTable {
    private let d: Data
    let syllableCount: Int
    private let sylIdxOff: Int
    private let sylBlobOff: Int
    private let unitsOff: Int
    private let keys: CodepointKeys
    private let blockStartOff: Int
    private let countsOff: Int
    private let readingsOff: Int

    private init(_ d: Data) {
        self.d = d
        syllableCount = Int(d.u32(4))
        sylIdxOff = Int(d.u32(24))
        sylBlobOff = Int(d.u32(28))
        unitsOff = Int(d.u32(32))
        keys = CodepointKeys(d, count: Int(d.u32(8)), bmpCount: Int(d.u32(12)), headsOff: Int(d.u32(36)))
        blockStartOff = Int(d.u32(48))
        countsOff = Int(d.u32(52))
        readingsOff = Int(d.u32(56))
    }

    static func of(_ d: Data) -> ZhuyinTable? {
        guard d.count >= 60, d[0] == 0x5A, d[1] == 0x59, d[2] == 0x4D, d[3] == 0x32 else { return nil }  // "ZYM2"
        return ZhuyinTable(d)
    }

    /// sylIdx（8B/筆）：strOff u16、strLen u8、unitCnt u8、unitStart u32
    func syllable(_ i: Int) -> String {
        let o = sylIdxOff + 8 * i
        return d.utf8String(sylBlobOff + Int(d.u16(o)), Int(d.u8(o + 2)))
    }

    /// 音節 i 的字（每個 code point 一個字串）
    func charsOfSyllable(_ i: Int) -> [String] {
        guard i >= 0, i < syllableCount else { return [] }
        let o = sylIdxOff + 8 * i
        return d.utf16Chars(unitsOff + 2 * Int(d.u32(o + 4)), Int(d.u8(o + 3)))
    }

    private func compareSyllable(_ i: Int, _ target: [UInt8]) -> Int {
        let o = sylIdxOff + 8 * i
        let off = sylBlobOff + Int(d.u16(o))
        let len = Int(d.u8(o + 2))
        let n = min(len, target.count)
        for j in 0..<n {
            let a = Int(d.u8(off + j)), b = Int(target[j])
            if a != b { return a - b }
        }
        return len - target.count
    }

    /// 注音字串 → 音節索引（依 UTF-8 位元組序二進位搜尋），查無回 −1
    func syllableIndex(_ zhuyin: String) -> Int {
        let target = Array(zhuyin.utf8)
        var lo = 0, hi = syllableCount - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let cmp = compareSyllable(mid, target)
            if cmp == 0 { return mid }
            if cmp < 0 { lo = mid + 1 } else { hi = mid - 1 }
        }
        return -1
    }

    func charsForZhuyin(_ zhuyin: String) -> [String] { charsOfSyllable(syllableIndex(zhuyin)) }

    /// 字 → 注音列表（順序 = 常用讀音在前）
    func zhuyinsOf(_ char: String) -> [String] {
        let scalars = char.unicodeScalars
        guard scalars.count == 1, let cp = scalars.first?.value else { return [] }
        let i = keys.indexOf(cp)
        guard i >= 0 else { return [] }
        let blk = i / CodepointKeys.block
        var start = Int(d.u16(blockStartOff + 2 * blk))
        for j in (blk * CodepointKeys.block)..<i { start += Int(d.u8(countsOff + j)) }
        let cnt = Int(d.u8(countsOff + i))
        var r: [String] = []
        r.reserveCapacity(cnt)
        for k in 0..<cnt {
            let s = Int(d.u16(readingsOff + 2 * (start + k)))
            if s < syllableCount { r.append(syllable(s)) }
        }
        return r
    }
}

/// PYM2：拼音 → 字。多數音節是 ZYM2 音節的別名（字表相同），少數原樣內嵌。
final class PinyinTable {
    private let d: Data
    private let zhuyin: ZhuyinTable
    private let count: Int
    private let idxOff: Int
    private let blobOff: Int
    private let unitsOff: Int

    private init(_ d: Data, zhuyin: ZhuyinTable) {
        self.d = d
        self.zhuyin = zhuyin
        count = Int(d.u32(4))
        idxOff = Int(d.u32(12))
        blobOff = Int(d.u32(16))
        unitsOff = Int(d.u32(20))
    }

    /// 建檔時的音節數須與手上的 ZYM2 一致，否則別名索引會指錯 → 視為無資料
    static func of(_ d: Data, zhuyin: ZhuyinTable) -> PinyinTable? {
        guard d.count >= 24, d[0] == 0x50, d[1] == 0x59, d[2] == 0x4D, d[3] == 0x32 else { return nil }  // "PYM2"
        guard Int(d.u32(8)) == zhuyin.syllableCount else { return nil }
        return PinyinTable(d, zhuyin: zhuyin)
    }

    /// idx（8B/筆）：strOff u16、strLen u8、unitCnt u8（0 = 別名）、ref u32
    private func compareKey(_ i: Int, _ target: [UInt8]) -> Int {
        let o = idxOff + 8 * i
        let off = blobOff + Int(d.u16(o))
        let len = Int(d.u8(o + 2))
        let n = min(len, target.count)
        for j in 0..<n {
            let a = Int(d.u8(off + j)), b = Int(target[j])
            if a != b { return a - b }
        }
        return len - target.count
    }

    func get(_ pinyin: String) -> [String] {
        guard count > 0 else { return [] }
        let target = Array(pinyin.utf8)
        var lo = 0, hi = count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let cmp = compareKey(mid, target)
            if cmp == 0 {
                let o = idxOff + 8 * mid
                let unitCnt = Int(d.u8(o + 3))
                let ref = Int(d.u32(o + 4))
                return unitCnt == 0 ? zhuyin.charsOfSyllable(ref) : d.utf16Chars(unitsOff + 2 * ref, unitCnt)
            }
            if cmp < 0 { lo = mid + 1 } else { hi = mid - 1 }
        }
        return []
    }
}

/// CFM2：codepoint → 頻次序。存 dense rank（0 = 最常用），回傳 0xFFFF − rank 當頻次，
/// 愈大愈常用；查無回 0（同 JSON 版語意，排序時墊底）。
final class CharFreqMap {
    private let d: Data
    private let count: Int
    private let keys: CodepointKeys
    private let ranksOff: Int

    private init(_ d: Data) {
        self.d = d
        count = Int(d.u32(4))
        keys = CodepointKeys(d, count: count, bmpCount: Int(d.u32(8)), headsOff: 12)
        ranksOff = 12 + keys.byteSize
    }

    static func of(_ d: Data) -> CharFreqMap? {
        guard d.count >= 12, d[0] == 0x43, d[1] == 0x46, d[2] == 0x4D, d[3] == 0x32 else { return nil }  // "CFM2"
        return CharFreqMap(d)
    }

    func get(codePoint: UInt32) -> Int {
        guard count > 0 else { return 0 }
        let i = keys.indexOf(codePoint)
        return i < 0 ? 0 : 0xFFFF - Int(d.u16(ranksOff + 2 * i))
    }

    /// 單一 codepoint 字串的頻次；其他長度回 0
    func get(_ char: String) -> Int {
        let scalars = char.unicodeScalars
        guard scalars.count == 1, let cp = scalars.first?.value else { return 0 }
        return get(codePoint: cp)
    }
}

// MARK: - Data helpers（u16/u32 在 WikiCorpus.swift）

extension Data {
    func u8(_ off: Int) -> UInt8 {
        guard off >= 0, off < count else { return 0 }
        return self[off]
    }

    func utf8String(_ start: Int, _ len: Int) -> String {
        guard start >= 0, len >= 0, start + len <= count else { return "" }
        return String(decoding: self[start..<(start + len)], as: UTF8.self)
    }

    /// 自 start 讀 unitCount 個 UTF-16LE code unit 成字串（越界回空）
    func utf16String(_ start: Int, _ unitCount: Int) -> String {
        guard start >= 0, unitCount >= 0, start + 2 * unitCount <= count else { return "" }
        var units = [UInt16](repeating: 0, count: unitCount)
        for j in 0..<unitCount { units[j] = u16(start + 2 * j) }
        return String(utf16CodeUnits: units, count: unitCount)
    }

    /// 自 start 讀 unitCount 個 UTF-16LE code unit，依 code point 切成一字一字串
    /// （surrogate pair 合成一字；越界或落單的 surrogate 略過）
    func utf16Chars(_ start: Int, _ unitCount: Int) -> [String] {
        guard start >= 0, unitCount >= 0, start + 2 * unitCount <= count else { return [] }
        var r: [String] = []
        r.reserveCapacity(unitCount)
        var i = 0
        while i < unitCount {
            let hi = u16(start + 2 * i)
            if UTF16.isLeadSurrogate(hi), i + 1 < unitCount {
                let lo = u16(start + 2 * (i + 1))
                if UTF16.isTrailSurrogate(lo) {
                    r.append(String(utf16CodeUnits: [hi, lo], count: 2))
                    i += 2
                    continue
                }
            }
            if !UTF16.isLeadSurrogate(hi), !UTF16.isTrailSurrogate(hi) {
                r.append(String(utf16CodeUnits: [hi], count: 1))
            }
            i += 1
        }
        return r
    }
}
