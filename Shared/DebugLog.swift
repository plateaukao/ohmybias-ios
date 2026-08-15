import Foundation

/// Writes timestamped debug logs to AppConstants.sharedDir/debug.log
/// 訊息用 @autoclosure 延遲建構 — debugMode 關閉（正常使用）時鍵擊路徑零字串組建。
enum DebugLog {
    private static var logPath: String { AppConstants.sharedDir + "/debug.log" }
    private static let maxSize = 512 * 1024  // 512 KB
    /// ISO8601DateFormatter 建構昂貴且執行緒安全 — 共用單一實例
    private static let formatter = ISO8601DateFormatter()

    static func log(_ msg: @autoclosure () -> String) {
        guard OhMyBiasPrefs.debugMode else { return }
        write(msg())
    }

    private static func write(_ msg: String) {
        let ts = formatter.string(from: Date())
        let line = "[\(ts)] \(msg)\n"
        let fm = FileManager.default
        let dir = AppConstants.sharedDir
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = logPath
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }
        // Rotate if too large
        if let attr = try? fm.attributesOfItem(atPath: path),
           let size = attr[.size] as? Int, size > maxSize {
            try? fm.removeItem(atPath: path + ".old")
            try? fm.moveItem(atPath: path, toPath: path + ".old")
            fm.createFile(atPath: path, contents: nil)
        }
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(line.data(using: .utf8)!)
            fh.closeFile()
        }
    }
}
