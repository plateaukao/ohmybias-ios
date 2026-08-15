import UIKit

/// 鍵盤主題 — 執行時讀 SkinSettings（匯入的 .cskin 調色盤/字級），
/// 未定義的鍵回退到內建 sweetlime 預設值（作者 Ryan 的「蝦米輸入法」皮膚）。
/// 手繪線稿風：淺色＝白鍵黑框、深色＝黑鍵灰框、功能鍵反白。
enum KeyboardTheme {

    /// 依 palette key 取動態色；skin 未定義時用預設 #RRGGBB(AA)
    private static func pal(_ key: String, _ lightDefault: String, _ darkDefault: String) -> UIColor {
        pal([key], lightDefault, darkDefault)
    }

    /// 帶別名鏈的取色：依序試 skin palette 的每個 key，全部未定義才用內建預設。
    /// 對應 sweetlime CskinParser 的 fallback（如 textSystem → 皮膚自己的 textMain）—
    /// 匯入皮膚缺 v2 鍵時必須鏈回皮膚內的相容色，跳到內建常數會產生暗底暗字。
    private static func pal(_ keys: [String], _ lightDefault: String, _ darkDefault: String) -> UIColor {
        UIColor { traits in
            // 鍵盤 extension 會繼承 host app 的 appearance；host 強制淺色時，
            // 仍應依系統外觀顯示使用者選擇的深色鍵盤。
            let style = UIScreen.main.traitCollection.userInterfaceStyle
            let dark = style == .unspecified
                ? traits.userInterfaceStyle == .dark
                : style == .dark
            for k in keys {
                if let hex = SkinSettings.shared.colorHex(k, dark: dark) { return parse(hex) }
            }
            return parse(dark ? darkDefault : lightDefault)
        }
    }

    private static func parse(_ s: String) -> UIColor {
        var v: UInt64 = 0
        Scanner(string: String(s.dropFirst())).scanHexInt64(&v)
        let hasAlpha = s.count > 7
        let a = hasAlpha ? CGFloat(v & 0xFF) / 255 : 1
        if hasAlpha { v >>= 8 }
        return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }

    // MARK: - 調色盤（palette key 同 cskin settings.json globalSettings.palette）

    /// 鍵盤整體背景
    static var background: UIColor { pal("bg", "#FFFFFF", "#000000") }
    /// 一般鍵背景／按下
    static var keyNormal: UIColor { pal("keyNormal", "#FFFFFF", "#000000") }
    static var keyNormalHighlight: UIColor { pal("keyNormalHighlight", "#EBEBEB", "#1A1A1A") }
    /// 功能鍵（shift、⌫、123…）背景／按下 — 深色模式反白
    static var keySystem: UIColor { pal("keySystem", "#D6D6D696", "#CCCCCC") }
    static var keySystemHighlight: UIColor { pal("keySystemHighlight", "#C7C7C7", "#BBBBBB") }
    /// Enter 鍵
    static var keyEnter: UIColor { pal("keyEnter", "#FFFFFF", "#CCCCCC") }
    static var keyEnterHighlight: UIColor { pal("keyEnterHighlight", "#C7C7C7", "#BBBBBB") }
    /// 主文字
    static var textMain: UIColor { pal("textMain", "#000000", "#BBBBBB") }
    /// 角標提示文字（上滑/下滑符號）
    static var textSub: UIColor { pal("textSub", "#666666", "#555555") }
    /// 功能鍵文字（內建深色設計鍵底反白故用深字；匯入皮膚未定義時鏈回其 textMain）
    static var textSystem: UIColor { pal(["textSystem", "textMain"], "#000000", "#1A1A1A") }
    /// 一般鍵邊框
    static var border: UIColor { pal("border", "#000000", "#BBBBBB") }
    /// 功能鍵邊框（未定義時鏈回皮膚的一般邊框）
    static var systemBorder: UIColor { pal(["systemBorder", "border"], "#000000", "#333333") }
    static var borderWidth: CGFloat {
        let dark = UIScreen.main.traitCollection.userInterfaceStyle == .dark
        return CGFloat(SkinSettings.shared.paletteNumber("borderSize", dark: dark) ?? 1)
    }
    static let cornerRadius: CGFloat = 8

    /// 工具列（背景未定義時鏈回皮膚的鍵盤背景 — 同 sweetlime）
    static var toolbarColor: UIColor { pal("toolbarColor", "#000000", "#CCCCCC") }
    static var toolbarBackground: UIColor { pal(["toolbarBg", "bg"], "#F0F0F0", "#000000") }

    /// 候選列
    static var candidateText: UIColor { pal("candidateUnselectedText", "#000000", "#CCCCCC") }
    static var candidateSelectedText: UIColor { pal("candidateSelectedText", "#000000", "#000000") }
    static var candidateSelectedBackground: UIColor { pal("candidateSelectedBg", "#FFFFFF", "#CCCCCC") }

    /// 面板（符號/emoji/顏文字）左欄分類、右欄內容（缺鍵時鏈回皮膚相容色）。
    /// 分類標籤是小型導覽文字 → 鏈回皮膚的高對比 textSub（textMain 可能是半透明鍵面字色）；
    /// 選中分類用皮膚保證成對的 candidateSelected 前景/背景。
    static var panelLeftBackground: UIColor { pal("panelLeftBg", "#F0F0F0", "#1C1C1E") }
    static var panelRightBackground: UIColor { pal("panelRightBg", "#FFFFFF", "#000000") }
    static var panelText: UIColor { pal(["panelLeftText", "textSub"], "#000000", "#F2F2F7") }
    static var panelCategoryHighlight: UIColor { pal(["panelCategoryHighlight", "candidateSelectedBg"], "#000000", "#F2F2F7") }
    static var panelCategorySelectedText: UIColor { pal(["panelCategorySelectedText", "candidateSelectedText"], "#F0F0F0", "#1C1C1E") }

    /// 長按氣泡（殼/選中底未定義時鏈回皮膚的功能鍵色，避免與氣泡文字撞色）
    static var bubbleShellBackground: UIColor { pal(["bubbleShellBg", "keySystemHighlight"], "#E9E2E2", "#FFFFFF") }
    static var bubbleSelectedBackground: UIColor { pal(["bubbleSelectedBg", "keySystem"], "#000000", "#1A1A1A") }
    static var bubbleTextSelected: UIColor { pal("bubbleTextSelected", "#FFFFFF", "#FFFFFF") }
    static var bubbleTextUnselected: UIColor { pal("bubbleTextUnselected", "#000000", "#1A1A1A") }

    // MARK: - 字級（cskin globalSettings.groups）

    private static func size(_ key: String, _ def: Double) -> CGFloat {
        CGFloat(SkinSettings.shared.fontSize(key, default: def))
    }

    static var alphabetFontSize: CGFloat { size("lowercaseSize", 23) }    // 小寫字母
    static var systemFontSize: CGFloat { size("systemSize", 16) }         // 功能鍵
    static var numberFontSize: CGFloat { size("numberSize", 24) }         // 數字鍵盤
    static var swipeHintFontSize: CGFloat { size("swipeSize", 10) }       // 角標
    static var toolbarIconSize: CGFloat { size("toolbarSize", 27) * 0.63 } // 工具列（27 為鍵高比例，轉字級）
    static var panelSymbolFontSize: CGFloat { size("panelLargeSymbolSize", 26) }
    static var panelKaomojiFontSize: CGFloat { size("panelLargeKaomojiSize", 20) }
    static var panelEmojiFontSize: CGFloat { size("panelLargeEmojiSize", 30) }
    static var panelSmallFontSize: CGFloat { size("panelSmallSize", 18) }
}
