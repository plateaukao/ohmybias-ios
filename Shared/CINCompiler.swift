import Foundation

/// Compiles a .cin text file into CINM binary format for mmap loading.
/// Called from App side after user imports a .cin file.
///
/// ⚠️  IMPORTANT: .cin files are copyrighted by their respective authors (e.g. 嘸蝦米 by 行易).
///    This compiler runs ON-DEVICE at import time only.
///    NEVER pre-compile or bundle .bin files — they are derived from copyrighted material.
enum CINCompiler {

    enum CompileError: Error {
        case unreadable    // 讀不到來源檔
        case undecodable   // 不是 UTF-8／UTF-16／Big5
        case noChardef     // 沒有 %chardef 區段，或區段內沒有任何字碼
        case writeFailed   // 寫不出 .bin
    }

    /// 解碼 .cin 文字：UTF-8（含 BOM）→ 帶 BOM 的 UTF-16 → Big5。
    /// 網路上流傳的 liu.cin 不少是早年 Windows 版嘸蝦米流出的 Big5 檔，Windows 記事本另存
    /// 又常帶 BOM 或存成 UTF-16 — 只認 UTF-8 會把這些全判成「無效的 .cin」。
    static func decode(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) {
            return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s
        }
        if data.count >= 2,
           (data[0] == 0xFF && data[1] == 0xFE) || (data[0] == 0xFE && data[1] == 0xFF),
           let s = String(data: data, encoding: .utf16) {
            return s
        }
        let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.big5.rawValue)))
        return String(data: data, encoding: big5)
    }

    /// Compile cin at `srcPath` → write bin to `dstPath`. Returns entry count or 0 on failure.
    @discardableResult
    static func compile(src srcPath: String, dst dstPath: String) -> Int {
        (try? compileDetailed(src: srcPath, dst: dstPath)) ?? 0
    }

    /// 同 compile，但失敗時丟出原因 — 匯入畫面據此給使用者具體的提示
    static func compileDetailed(src srcPath: String, dst dstPath: String) throws -> Int {
        guard let data = FileManager.default.contents(atPath: srcPath) else { throw CompileError.unreadable }
        guard let content = decode(data) else { throw CompileError.undecodable }

        var entries: [(code: String, chars: [String])] = []
        var codeMap: [String: Int] = [:]  // code → index in entries
        var selkeys = "0123456789"
        var cname = ""
        var inChardef = false

        content.enumerateLines { line, _ in
            let t = line.trimmingCharacters(in: .whitespaces)
            // 指令列以任意空白（空格／tab、可多個）分隔 — 舊版只認單一空格，
            // 「%chardef<tab>begin」會整份讀不到字碼
            if t.hasPrefix("%") {
                let words = t.split(whereSeparator: { $0 == " " || $0 == "\t" })
                switch words.first {
                case "%selkey": if words.count >= 2 { selkeys = String(words[1]) }
                case "%cname": if words.count >= 2 { cname = words.dropFirst().joined(separator: " ") }
                case "%chardef": if words.count >= 2 { inChardef = (words[1] == "begin") }
                default: break
                }
                return
            }
            guard inChardef else { return }
            let parts: [String]
            if t.contains("\t") { parts = t.split(separator: "\t", maxSplits: 1).map(String.init) }
            else { parts = t.split(separator: " ", maxSplits: 1).map(String.init) }
            guard parts.count == 2 else { return }
            let code = parts[0].lowercased()
            let char = parts[1].trimmingCharacters(in: .whitespaces)
            if let idx = codeMap[code] {
                entries[idx].chars.append(char)
            } else {
                codeMap[code] = entries.count
                entries.append((code, [char]))
            }
        }

        // Sort by code (ASCII order)
        entries.sort { $0.code < $1.code }
        guard !entries.isEmpty else { throw CompileError.noChardef }

        // Build strings section
        var stringsBuf = Data()
        var codeEntries: [(off: Int, len: Int)] = []
        for e in entries {
            let b = e.code.data(using: .ascii) ?? Data()
            codeEntries.append((stringsBuf.count, b.count))
            stringsBuf.append(b)
        }

        // Build chars section
        var charsBuf = Data()
        var valEntries: [(off: Int, cnt: Int)] = []
        for e in entries {
            let off = charsBuf.count / 4
            var cnt = 0
            for ch in e.chars {
                for scalar in ch.unicodeScalars {
                    var cp = scalar.value.littleEndian
                    charsBuf.append(Data(bytes: &cp, count: 4))
                    cnt += 1
                }
            }
            valEntries.append((off, cnt))
        }

        // Header (128 bytes)
        let headerSize = 128
        var header = Data(count: headerSize)
        header[0] = 0x43; header[1] = 0x49; header[2] = 0x4E; header[3] = 0x4D // "CINM"
        header.writeU32(4, UInt32(entries.count))
        let skData = selkeys.data(using: .ascii) ?? Data()
        header[8] = UInt8(min(skData.count, 10))
        header.replaceSubrange(9..<(9 + min(skData.count, 10)), with: skData.prefix(10))
        let cnData = (cname.data(using: .utf8) ?? Data()).prefix(64)
        header.writeU16(20, UInt16(cnData.count))
        header.replaceSubrange(22..<(22 + cnData.count), with: cnData)

        // Code index
        var codeIdx = Data()
        for e in codeEntries {
            codeIdx.appendU32(UInt32(e.off))
            codeIdx.appendU16(UInt16(e.len))
        }

        // Val index
        var valIdx = Data()
        for e in valEntries {
            guard e.off <= Int(UInt16.max) else {
                valIdx.appendU16(UInt16.max)
                valIdx.append(UInt8(min(e.cnt, 255)))
                valIdx.append(0)
                continue
            }
            valIdx.appendU16(UInt16(e.off))
            valIdx.append(UInt8(min(e.cnt, 255)))
            valIdx.append(0) // reserved
        }

        // Section offsets
        let codesOff = headerSize
        let valsOff = codesOff + codeIdx.count
        let stringsOff = valsOff + valIdx.count
        let charsOff = stringsOff + stringsBuf.count
        header.writeU32(96, UInt32(codesOff))
        header.writeU32(100, UInt32(valsOff))
        header.writeU32(104, UInt32(stringsOff))
        header.writeU32(108, UInt32(charsOff))

        // Assemble + write
        var buf = header
        buf.append(codeIdx)
        buf.append(valIdx)
        buf.append(stringsBuf)
        buf.append(charsBuf)

        do {
            try buf.write(to: URL(fileURLWithPath: dstPath))
            return entries.count
        } catch {
            throw CompileError.writeFailed
        }
    }
}

// MARK: - Data write helpers
private extension Data {
    mutating func writeU32(_ off: Int, _ v: UInt32) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { replaceSubrange(off..<(off+4), with: $0) }
    }
    mutating func writeU16(_ off: Int, _ v: UInt16) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { replaceSubrange(off..<(off+2), with: $0) }
    }
    mutating func appendU32(_ v: UInt32) {
        var le = v.littleEndian
        append(Data(bytes: &le, count: 4))
    }
    mutating func appendU16(_ v: UInt16) {
        var le = v.littleEndian
        append(Data(bytes: &le, count: 2))
    }
}
