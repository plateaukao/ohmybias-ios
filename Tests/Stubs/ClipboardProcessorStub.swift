import Foundation

/// 測試在 macOS host 上編譯，真正的 ClipboardProcessor 用 UIKit（被 run_tests.sh 排除）。
enum ClipboardProcessor {
    static var stubText: String?

    static func plainText() -> String? { stubText }

    static func toTraditional(_ text: String) -> String {
        text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
    }

    static func toSimplified(_ text: String) -> String {
        text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
    }
}
