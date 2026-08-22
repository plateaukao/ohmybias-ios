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
    /// 效能：淺/深兩色在「建色時」就解析完（皮膚查找＋十六進位解析只做一次），
    /// dynamic provider 每次 resolve 只挑淺或深 — 不再每次繪製重查皮膚。
    private static func pal(_ keys: [String], _ lightDefault: String, _ darkDefault: String) -> UIColor {
        func resolve(dark: Bool) -> UIColor {
            for k in keys {
                if let hex = SkinSettings.shared.colorHex(k, dark: dark) { return parse(hex) }
            }
            return parse(dark ? darkDefault : lightDefault)
        }
        let light = resolve(dark: false)
        let darkColor = resolve(dark: true)
        // provider 必須是傳入 traits 的純函數 — UIKit 只在視圖 trait 改變時重解動態色。
        // 在此讀 UIScreen 等全域狀態會卡舊主題：extension 行程的 UIScreen traits
        // 不跟著系統外觀更新（深淺色切換不重繪的根因）。外觀完全跟隨繼承 trait —
        // 詳見 KeyboardViewController 內「深淺色」註解。
        return UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkColor : light
        }
    }

    // MARK: - 解析快取（每皮膚世代解析一次；主執行緒專用）

    private static var colorCache: [String: UIColor] = [:]
    private static var cachedGeneration = -1

    /// 依名稱快取建好的 UIColor（dynamic provider 物件可跨深淺色共用）；
    /// 皮膚世代改變時整批失效 — 對應 Android 版 KeyboardTheme.Resolved
    private static func cached(_ name: String, _ make: () -> UIColor) -> UIColor {
        let g = SkinSettings.shared.generation
        if cachedGeneration != g {
            colorCache.removeAll(keepingCapacity: true)
            cachedGeneration = g
        }
        if let c = colorCache[name] { return c }
        let c = make()
        colorCache[name] = c
        return c
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

    /// iOS 27 液態玻璃：系統背板是透明玻璃，鍵盤/工具列背景不再自畫（交給系統）。
    static var glassHost: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    /// 皮膚鍵面色常帶 alpha（設計上假設疊在不透明背景上），直接放上玻璃會成鬼影 —
    /// 玻璃模式下以皮膚工具列/鍵盤背景為底壓成不透明，視覺等同舊版疊色結果；
    /// 鍵與鍵之間的空隙留給系統玻璃。非玻璃模式原樣回傳。
    private static func solid(_ color: UIColor) -> UIColor {
        guard glassHost else { return color }
        let base = toolbarBackground
        return UIColor { traits in
            func rgba(_ c: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                c.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
                return (r, g, b, a)
            }
            // 底色自身也可能帶 alpha → 先壓在純白/純黑地上（深淺判斷同 pal：只看傳入 traits）
            let ground: CGFloat = traits.userInterfaceStyle == .dark ? 0 : 1
            let b = rgba(base)
            let gr = b.r * b.a + ground * (1 - b.a)
            let gg = b.g * b.a + ground * (1 - b.a)
            let gb = b.b * b.a + ground * (1 - b.a)
            let t = rgba(color)
            return UIColor(red: t.r * t.a + gr * (1 - t.a),
                           green: t.g * t.a + gg * (1 - t.a),
                           blue: t.b * t.a + gb * (1 - t.a), alpha: 1)
        }
    }

    // MARK: - 調色盤（palette key 同 cskin settings.json globalSettings.palette）

    /// 鍵盤整體背景
    static var background: UIColor { cached("background") { pal("bg", "#FFFFFF", "#000000") } }
    /// 一般鍵背景／按下（玻璃模式壓成不透明 — 鍵面必須是實色）
    static var keyNormal: UIColor { cached("keyNormal") { solid(pal("keyNormal", "#FFFFFF", "#000000")) } }
    static var keyNormalHighlight: UIColor { cached("keyNormalHighlight") { solid(pal("keyNormalHighlight", "#EBEBEB", "#1A1A1A")) } }
    /// 功能鍵（shift、⌫、123…）背景／按下 — 深色模式反白
    static var keySystem: UIColor { cached("keySystem") { solid(pal("keySystem", "#D6D6D696", "#CCCCCC")) } }
    static var keySystemHighlight: UIColor { cached("keySystemHighlight") { solid(pal("keySystemHighlight", "#C7C7C7", "#BBBBBB")) } }
    /// Enter 鍵
    static var keyEnter: UIColor { cached("keyEnter") { solid(pal("keyEnter", "#FFFFFF", "#CCCCCC")) } }
    static var keyEnterHighlight: UIColor { cached("keyEnterHighlight") { solid(pal("keyEnterHighlight", "#C7C7C7", "#BBBBBB")) } }
    /// 主文字
    static var textMain: UIColor { cached("textMain") { pal("textMain", "#000000", "#BBBBBB") } }
    /// 角標提示文字（上滑/下滑符號）
    static var textSub: UIColor { cached("textSub") { pal("textSub", "#666666", "#555555") } }
    /// 功能鍵文字（內建深色設計鍵底反白故用深字；匯入皮膚未定義時鏈回其 textMain）
    static var textSystem: UIColor { cached("textSystem") { pal(["textSystem", "textMain"], "#000000", "#1A1A1A") } }
    /// 一般鍵邊框
    static var border: UIColor { cached("border") { pal("border", "#000000", "#BBBBBB") } }
    /// 功能鍵邊框（未定義時鏈回皮膚的一般邊框）
    static var systemBorder: UIColor { cached("systemBorder") { pal(["systemBorder", "border"], "#000000", "#333333") } }
    /// 按下時的邊框色（未定義時鏈回該鍵平時的邊框色 → 舊皮膚外觀不變）
    static var borderHighlight: UIColor { cached("borderHighlight") { pal(["borderHighlight", "border"], "#000000", "#BBBBBB") } }
    static var systemBorderHighlight: UIColor {
        cached("systemBorderHighlight") { pal(["systemBorderHighlight", "systemBorder", "border"], "#000000", "#333333") }
    }
    /// 邊框寬依皮膚淺/深色調色盤可能不同 — 以呼叫端視圖的 traits 判斷，勿讀全域外觀
    static func borderWidth(for traits: UITraitCollection) -> CGFloat {
        let dark = traits.userInterfaceStyle == .dark
        return CGFloat(SkinSettings.shared.paletteNumber("borderSize", dark: dark) ?? 1)
    }
    /// 按下時的邊框寬（未定義時同平時邊框寬）
    static func borderWidthHighlight(for traits: UITraitCollection) -> CGFloat {
        let dark = traits.userInterfaceStyle == .dark
        if let v = SkinSettings.shared.paletteNumber("borderSizeHighlight", dark: dark) { return CGFloat(v) }
        return borderWidth(for: traits)
    }
    static let cornerRadius: CGFloat = 8

    /// 工具列（背景未定義時鏈回皮膚的鍵盤背景 — 同 sweetlime）
    static var toolbarColor: UIColor { cached("toolbarColor") { pal("toolbarColor", "#000000", "#CCCCCC") } }
    static var toolbarBackground: UIColor { cached("toolbarBackground") { pal(["toolbarBg", "bg"], "#F0F0F0", "#000000") } }

    /// 候選列
    static var candidateText: UIColor { cached("candidateText") { pal("candidateUnselectedText", "#000000", "#CCCCCC") } }
    static var candidateSelectedText: UIColor { cached("candidateSelectedText") { pal("candidateSelectedText", "#000000", "#000000") } }
    static var candidateSelectedBackground: UIColor { cached("candidateSelectedBackground") { solid(pal("candidateSelectedBg", "#FFFFFF", "#CCCCCC")) } }

    /// 面板（符號/emoji/顏文字）左欄分類、右欄內容（缺鍵時鏈回皮膚相容色）。
    /// 分類標籤是小型導覽文字 → 鏈回皮膚的高對比 textSub（textMain 可能是半透明鍵面字色）；
    /// 選中分類用皮膚保證成對的 candidateSelected 前景/背景。
    static var panelLeftBackground: UIColor { cached("panelLeftBackground") { solid(pal("panelLeftBg", "#F0F0F0", "#1C1C1E")) } }
    static var panelRightBackground: UIColor { cached("panelRightBackground") { solid(pal("panelRightBg", "#FFFFFF", "#000000")) } }
    static var panelText: UIColor { cached("panelText") { pal(["panelLeftText", "textSub"], "#000000", "#F2F2F7") } }
    static var panelCategoryHighlight: UIColor { cached("panelCategoryHighlight") { solid(pal(["panelCategoryHighlight", "candidateSelectedBg"], "#000000", "#F2F2F7")) } }
    static var panelCategorySelectedText: UIColor { cached("panelCategorySelectedText") { pal(["panelCategorySelectedText", "candidateSelectedText"], "#F0F0F0", "#1C1C1E") } }

    /// 長按氣泡（殼/選中底未定義時鏈回皮膚的功能鍵色，避免與氣泡文字撞色）
    static var bubbleShellBackground: UIColor { cached("bubbleShellBackground") { solid(pal(["bubbleShellBg", "keySystemHighlight"], "#E9E2E2", "#FFFFFF")) } }
    static var bubbleSelectedBackground: UIColor { cached("bubbleSelectedBackground") { solid(pal(["bubbleSelectedBg", "keySystem"], "#000000", "#1A1A1A")) } }
    static var bubbleTextSelected: UIColor { cached("bubbleTextSelected") { pal("bubbleTextSelected", "#FFFFFF", "#FFFFFF") } }
    static var bubbleTextUnselected: UIColor { cached("bubbleTextUnselected") { pal("bubbleTextUnselected", "#000000", "#1A1A1A") } }

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
