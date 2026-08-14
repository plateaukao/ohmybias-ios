import Foundation

/// cskin 皮膚設定 — 讀取匯入的 .cskin 內 `jsonnet/settings.json`（存於 App Group
/// 的 skin_settings.json）。未匯入時用內建 sweetlime 預設值。
/// 只讀「配置」層（工具列/調色盤/字級/版面選項）；jsonnet 鍵盤佈局編譯不在此層。
final class SkinSettings {
    static let shared = SkinSettings()

    static var settingsPath: String { AppConstants.sharedDir + "/skin_settings.json" }

    /// 內建預設工具列（sweetlime toolbarButtons，全選(10)位置依使用者決定放 ♥ 常用語(5)）
    static let defaultToolbarButtons = [1, 3, 9, 7, 16, 17, 8, 5, 13, 2]

    private(set) var skinName = "sweetlime（內建）"
    private(set) var isImported = false
    private(set) var toolbarButtons: [Int] = SkinSettings.defaultToolbarButtons
    /// 'panel' = 九宮格數字、'row' = Row 數字
    private(set) var keyboardLayout = "panel"
    /// '1' 空白最小（逗號句號較大）、'2' 適中、'3' 空白最大
    private(set) var spaceKeyLayout = "3"
    /// '2' 長按選單大寫在首位、'1' 小寫在首位
    private(set) var longPressLayout = "2"
    /// 全域開關：swipeUp / swipeDown / longPress / showSwipeUpText / showSwipeDownText
    private(set) var enabledFeatures: Set<String> = [
        "swipeUp", "swipeDown", "longPress", "showSwipeUpText", "showSwipeDownText",
    ]
    private var paletteLight: [String: Any] = [:]
    private var paletteDark: [String: Any] = [:]
    private var fontGroups: [String: Double] = [:]

    private init() { reload() }

    func reload() {
        // 重設為內建預設
        skinName = "sweetlime（內建）"
        isImported = false
        toolbarButtons = Self.defaultToolbarButtons
        keyboardLayout = "panel"
        spaceKeyLayout = "3"
        longPressLayout = "2"
        enabledFeatures = ["swipeUp", "swipeDown", "longPress", "showSwipeUpText", "showSwipeDownText"]
        paletteLight = [:]; paletteDark = [:]; fontGroups = [:]

        guard let data = FileManager.default.contents(atPath: Self.settingsPath) else { return }
        apply(jsonData: data)
    }

    /// 解析 settings.json 內容（獨立出來供測試餵資料）
    func apply(jsonData: Data) {
        guard let root = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any] else { return }
        isImported = true
        if let info = root["skinInfo"] as? [String: Any], let name = info["name"] as? String {
            skinName = name
        }
        if let toolbar = root["toolbar"] as? [String: Any],
           let buttons = toolbar["toolbarButtons"] as? [Any] {
            let ids = buttons.compactMap { ($0 as? NSNumber)?.intValue }
            if !ids.isEmpty { toolbarButtons = ids }
        }
        if let layout = root["layout"] as? [String: Any] {
            if let v = layout["keyboardLayout"] as? String { keyboardLayout = v }
            if let v = layout["spaceKeyLayout"] as? String { spaceKeyLayout = v }
            if let v = layout["longPressLayout"] as? String { longPressLayout = v }
        }
        if let swipe = root["swipe"] as? [String: Any],
           let features = swipe["globalEnabledFeatures"] as? [String] {
            enabledFeatures = Set(features)
        }
        if let global = root["globalSettings"] as? [String: Any] {
            if let palette = global["palette"] as? [String: Any] {
                paletteLight = palette["light"] as? [String: Any] ?? [:]
                paletteDark = palette["dark"] as? [String: Any] ?? [:]
            }
            if let groups = global["groups"] as? [String: Any] {
                fontGroups = groups.compactMapValues { ($0 as? NSNumber)?.doubleValue }
            }
        }
    }

    // MARK: - 查詢

    var swipeUpEnabled: Bool { enabledFeatures.contains("swipeUp") }
    var swipeDownEnabled: Bool { enabledFeatures.contains("swipeDown") }
    var longPressEnabled: Bool { enabledFeatures.contains("longPress") }
    var showSwipeUpText: Bool { enabledFeatures.contains("showSwipeUpText") }
    var showSwipeDownText: Bool { enabledFeatures.contains("showSwipeDownText") }

    /// 調色盤色值（#RRGGBB / #RRGGBBAA 字串）；未定義回 nil 由呼叫端用預設
    func colorHex(_ key: String, dark: Bool) -> String? {
        (dark ? paletteDark : paletteLight)[key] as? String
    }

    /// 調色盤數值（如 borderSize）
    func paletteNumber(_ key: String, dark: Bool) -> Double? {
        ((dark ? paletteDark : paletteLight)[key] as? NSNumber)?.doubleValue
    }

    /// 字級（globalSettings.groups）
    func fontSize(_ key: String, default def: Double) -> Double {
        fontGroups[key] ?? def
    }
}
