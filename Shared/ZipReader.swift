import Foundation
import Compression

/// 極簡 ZIP 讀取器 — 供匯入 .cskin（zip 容器）取出單一檔案用。零依賴：
/// 自行解析 central directory，STORE 直接切片、DEFLATE 用系統 Compression 解。
enum ZipReader {

    struct Entry {
        let name: String          // UTF-8 解碼；失敗時以 Latin-1 呈現（僅供比對後綴）
        let method: UInt16        // 0 = store, 8 = deflate
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    /// 列出 zip 內所有 entry
    static func entries(in data: Data) -> [Entry] {
        // 從檔尾找 End of Central Directory（0x06054b50）
        let eocdSig: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        let searchStart = max(0, data.count - 65_557)
        var eocdPos = -1
        var i = data.count - 22
        while i >= searchStart {
            if data[i] == eocdSig[0], data[i+1] == eocdSig[1], data[i+2] == eocdSig[2], data[i+3] == eocdSig[3] {
                eocdPos = i; break
            }
            i -= 1
        }
        guard eocdPos >= 0 else { return [] }
        let count = Int(u16(data, eocdPos + 10))
        var offset = Int(u32(data, eocdPos + 16))

        var result: [Entry] = []
        for _ in 0..<count {
            guard offset + 46 <= data.count, u32(data, offset) == 0x0201_4b50 else { break }
            let method = u16(data, offset + 10)
            let compSize = Int(u32(data, offset + 20))
            let uncompSize = Int(u32(data, offset + 24))
            let nameLen = Int(u16(data, offset + 28))
            let extraLen = Int(u16(data, offset + 30))
            let commentLen = Int(u16(data, offset + 32))
            let localOffset = Int(u32(data, offset + 42))
            let nameData = data.subdata(in: (offset + 46)..<(offset + 46 + nameLen))
            let name = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? ""
            result.append(Entry(name: name, method: method, compressedSize: compSize,
                                uncompressedSize: uncompSize, localHeaderOffset: localOffset))
            offset += 46 + nameLen + extraLen + commentLen
        }
        return result
    }

    /// 取出單一 entry 的內容
    static func extract(_ entry: Entry, from data: Data) -> Data? {
        let off = entry.localHeaderOffset
        guard off + 30 <= data.count, u32(data, off) == 0x0403_4b50 else { return nil }
        let nameLen = Int(u16(data, off + 26))
        let extraLen = Int(u16(data, off + 28))
        let start = off + 30 + nameLen + extraLen
        guard start + entry.compressedSize <= data.count else { return nil }
        let comp = data.subdata(in: start..<(start + entry.compressedSize))

        switch entry.method {
        case 0:
            return comp
        case 8:
            return inflate(comp, expectedSize: entry.uncompressedSize)
        default:
            return nil
        }
    }

    /// 找出第一個名稱以 suffix 結尾的 entry 並取出
    static func extractFirst(named suffix: String, from data: Data) -> Data? {
        guard let entry = entries(in: data).first(where: { $0.name.hasSuffix(suffix) }) else { return nil }
        return extract(entry, from: data)
    }

    // MARK: - Helpers

    private static func u16(_ d: Data, _ i: Int) -> UInt16 {
        UInt16(d[i]) | (UInt16(d[i+1]) << 8)
    }

    private static func u32(_ d: Data, _ i: Int) -> UInt32 {
        UInt32(d[i]) | (UInt32(d[i+1]) << 8) | (UInt32(d[i+2]) << 16) | (UInt32(d[i+3]) << 24)
    }

    /// raw DEFLATE 解壓（zip method 8 無 zlib header，對應 Compression 的 COMPRESSION_ZLIB）
    private static func inflate(_ comp: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        var dst = Data(count: expectedSize)
        let written = dst.withUnsafeMutableBytes { dstPtr in
            comp.withUnsafeBytes { srcPtr in
                compression_decode_buffer(
                    dstPtr.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                    srcPtr.bindMemory(to: UInt8.self).baseAddress!, comp.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { return nil }
        return dst
    }
}
