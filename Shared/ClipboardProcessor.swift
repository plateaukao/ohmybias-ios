import Foundation
import UIKit

enum ClipboardProcessor {

    /// Read plain text from clipboard (strips all formatting).
    /// 鍵盤 extension 未開啟「完整取用權限」時回傳 nil。
    static func plainText() -> String? {
        UIPasteboard.general.string
    }

    /// Simplified → Traditional Chinese
    static func toTraditional(_ text: String) -> String {
        text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
    }

    /// Traditional → Simplified Chinese
    static func toSimplified(_ text: String) -> String {
        text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
    }
}
