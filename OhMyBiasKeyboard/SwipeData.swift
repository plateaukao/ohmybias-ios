import UIKit

/// 按鍵上滑/下滑動作表 — 取自 sweetlime 皮膚 swipeData.libsonnet。
/// 上滑＝符號、下滑＝數字；第三排下滑＝編輯功能（行首/貼上/Tab/行尾）。
/// 皮膚中的剪下/複製/全選需 host app 配合，iOS 鍵盤 extension 無 API，故不移植。
enum SwipeData {

    struct Entry {
        let hint: String?      // 鍵帽角標（nil = 不顯示）
        let action: KeyAction
    }

    /// 字母頁上滑（中英共用；動作皆半形直接輸出）
    static let up: [String: Entry] = [
        "q": Entry(hint: "!", action: .symbol("!")),
        "w": Entry(hint: "@", action: .symbol("@")),
        "e": Entry(hint: "#", action: .symbol("#")),
        "r": Entry(hint: "$", action: .symbol("$")),
        "t": Entry(hint: "%", action: .symbol("%")),
        "y": Entry(hint: "^", action: .symbol("^")),
        "u": Entry(hint: "&", action: .symbol("&")),
        "i": Entry(hint: "*", action: .symbol("*")),
        "o": Entry(hint: "(", action: .symbol("(")),
        "p": Entry(hint: ")", action: .symbol(")")),
        "a": Entry(hint: "`", action: .symbol("`")),
        "s": Entry(hint: "-", action: .symbol("-")),
        "d": Entry(hint: "=", action: .symbol("=")),
        "f": Entry(hint: "【", action: .symbol("【")),
        "g": Entry(hint: "】", action: .symbol("】")),
        "h": Entry(hint: "\\", action: .symbol("\\")),
        "j": Entry(hint: "/", action: .symbol("/")),
        "k": Entry(hint: "；", action: .symbol(";")),
        "l": Entry(hint: "'", action: .symbol("'")),
        "x": Entry(hint: "[", action: .symbol("[")),
        "c": Entry(hint: "]", action: .symbol("]")),
        "v": Entry(hint: "<", action: .symbol("<")),
        "b": Entry(hint: ">", action: .symbol(">")),
        "n": Entry(hint: "2nd", action: .selectCandidateShortcut(1)),
        "m": Entry(hint: "3rd", action: .selectCandidateShortcut(2)),
        ",": Entry(hint: nil, action: .symbol(",")),
        ".": Entry(hint: nil, action: .symbol(".")),
    ]

    /// 字母頁下滑
    static let down: [String: Entry] = [
        "q": Entry(hint: "1", action: .symbol("1")),
        "w": Entry(hint: "2", action: .symbol("2")),
        "e": Entry(hint: "3", action: .symbol("3")),
        "r": Entry(hint: "4", action: .symbol("4")),
        "t": Entry(hint: "5", action: .symbol("5")),
        "y": Entry(hint: "6", action: .symbol("6")),
        "u": Entry(hint: "7", action: .symbol("7")),
        "i": Entry(hint: "8", action: .symbol("8")),
        "o": Entry(hint: "9", action: .symbol("9")),
        "p": Entry(hint: "0", action: .symbol("0")),
        "a": Entry(hint: "~", action: .symbol("~")),
        "s": Entry(hint: "_", action: .symbol("_")),
        "d": Entry(hint: "+", action: .symbol("+")),
        "f": Entry(hint: "{", action: .symbol("{")),
        "g": Entry(hint: "}", action: .symbol("}")),
        "h": Entry(hint: "|", action: .symbol("|")),
        "j": Entry(hint: "?", action: .symbol("?")),
        "k": Entry(hint: ":", action: .symbol(":")),
        "l": Entry(hint: "\"", action: .symbol("\"")),
        "z": Entry(hint: "句首", action: .lineStart),
        "v": Entry(hint: "貼上", action: .pasteClipboard),
        "b": Entry(hint: "Tab", action: .tab),
        "m": Entry(hint: "句尾", action: .lineEnd),
        ",": Entry(hint: nil, action: .symbol("、")),
        ".": Entry(hint: nil, action: .symbol("！")),
    ]
}
