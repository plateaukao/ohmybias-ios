import Foundation

/// 長按選單資料 — 取自 sweetlime 皮膚 hintSymbolsData.libsonnet（longPressLayout '2'：大寫在首位）。
/// 字母鍵：大寫/小寫/變音符變體直接輸出；左半鍵盤選單向右展開（預設在首）、
/// 右半鍵盤鏡像（預設在尾），避免選單超出螢幕。
/// 逗號/句號鍵：皮膚原以 Rime 腳本輸出時間日期，此處以 Foundation 曆法原生實作。
enum LongPressData {

    struct Option {
        let label: String
        /// nil = 直接輸出 label；非 nil = 選取時動態產生（日期時間）
        let dateKind: DateKind?
        init(_ label: String, _ dateKind: DateKind? = nil) {
            self.label = label
            self.dateKind = dateKind
        }
    }

    struct Menu {
        let options: [Option]
        let defaultIndex: Int
    }

    enum DateKind {
        case time          // 21:03
        case dateSlash     // 2026/08/14
        case dateChinese   // 二〇二六年八月十四日
        case dateROC       // 民國115年8月14日
        case dateJapanese  // 令和8年8月14日
        case dateEnglish   // August 14, 2026
        case dateLunar     // 丙午年七月初二
        case timeZone      // GMT+8
    }

    /// 選取時解析選項為實際輸出文字
    static func resolve(_ option: Option) -> String {
        guard let kind = option.dateKind else { return option.label }
        let now = Date()
        switch kind {
        case .time:         return format(now, .gregorian, "zh_Hant_TW", "HH:mm")
        case .dateSlash:    return format(now, .gregorian, "zh_Hant_TW", "yyyy/MM/dd")
        case .dateChinese:  return chineseDate(now)
        case .dateROC:      return format(now, .republicOfChina, "zh_Hant_TW", "Gy年M月d日")
        case .dateJapanese: return format(now, .japanese, "ja_JP", "Gy年M月d日")
        case .dateEnglish:  return format(now, .gregorian, "en_US", "MMMM d, yyyy")
        case .dateLunar:    return lunarDate(now)
        case .timeZone:     return TimeZone.current.abbreviation() ?? TimeZone.current.identifier
        }
    }

    private static func format(_ date: Date, _ cal: Calendar.Identifier, _ locale: String, _ fmt: String) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: cal)
        f.locale = Locale(identifier: locale)
        f.dateFormat = fmt
        return f.string(from: date)
    }

    /// 二〇二六年八月十四日
    private static func chineseDate(_ date: Date) -> String {
        let comps = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        let digits: [Character] = ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        let year = String(comps.year!).compactMap { $0.wholeNumberValue.map { digits[$0] } }
        func number(_ n: Int) -> String {
            // 1–31：十進位中文讀法（十四、二十一）
            if n <= 10 { return n == 10 ? "十" : String(digits[n]) }
            let tens = n / 10, ones = n % 10
            let head = tens == 1 ? "十" : "\(digits[tens])十"
            return ones == 0 ? head : head + String(digits[ones])
        }
        return "\(String(year))年\(number(comps.month!))月\(number(comps.day!))日"
    }

    /// 丙午年七月初二（去掉開頭的西元年數字）
    private static func lunarDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .chinese)
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateStyle = .long
        return String(f.string(from: date).drop(while: { $0.isNumber }))
    }

    // MARK: - 字母鍵選單

    /// 各字母的變音符變體（小寫, 大寫）— 同 sweetlime
    private static let accents: [String: (String, String)] = [
        "q": ("ɋ", "Ɋ"), "w": ("ẁ", "Ẁ"), "e": ("ē", "Ē"), "r": ("ŕ", "Ŕ"), "t": ("ṫ", "Ṫ"),
        "y": ("ȳ", "Ȳ"), "u": ("ū", "Ū"), "i": ("ī", "Ī"), "o": ("ō", "Ō"), "p": ("ṕ", "Ṕ"),
        "a": ("ā", "Ā"), "s": ("ś", "Ś"), "d": ("ḋ", "Ḋ"), "f": ("ḟ", "Ḟ"), "g": ("ḡ", "Ḡ"),
        "h": ("ḣ", "Ḣ"), "j": ("ĵ", "Ĵ"), "k": ("ḱ", "Ḱ"), "l": ("ĺ", "Ĺ"),
        "z": ("ź", "Ź"), "x": ("ẋ", "Ẋ"), "c": ("ć", "Ć"), "v": ("ṽ", "Ṽ"),
        "b": ("ḃ", "Ḃ"), "n": ("ń", "Ń"), "m": ("ḿ", "Ḿ"),
    ]

    /// 左半鍵盤（選單自鍵位向右展開）
    private static let leftHalf: Set<String> = ["q", "w", "e", "r", "t", "a", "s", "d", "f", "g", "z", "x", "c", "v"]

    /// 字母鍵長按選單；key 為小寫字母。
    /// 順序依 cskin longPressLayout：'2' 大寫在首位（預設）、'1' 小寫在首位。
    static func letterMenu(_ key: String) -> Menu? {
        guard let (accLower, accUpper) = accents[key] else { return nil }
        let upper = key.uppercased()
        let upperFirst = SkinSettings.shared.longPressLayout != "1"
        let near: [Option] = upperFirst
            ? [Option(upper), Option(key), Option(accUpper), Option(accLower)]
            : [Option(key), Option(upper), Option(accLower), Option(accUpper)]
        if leftHalf.contains(key) {
            return Menu(options: near, defaultIndex: 0)
        } else {
            return Menu(options: near.reversed(), defaultIndex: near.count - 1)
        }
    }

    /// 逗號鍵：時間/日期插入
    static let commaMenu = Menu(options: [
        Option("時間", .time),
        Option("日期", .dateSlash),
        Option("中文", .dateChinese),
        Option("民國", .dateROC),
        Option("日本", .dateJapanese),
    ], defaultIndex: 0)

    /// 句號鍵：英文/農曆/時區（皮膚的組合/節氣為 Rime 腳本，不移植）
    static let periodMenu = Menu(options: [
        Option("英文", .dateEnglish),
        Option("農曆", .dateLunar),
        Option("時區", .timeZone),
    ], defaultIndex: 0)
}
