import Foundation

/// 工具列項目的跨平台定義；鍵盤與容器 app 共用，避免設定頁選到鍵盤不認識的項目。
enum ToolbarItems {
    static let placeholder = 0
    static let slotCount = 10

    struct Definition: Identifiable, Equatable {
        let id: Int
        let icon: String?
        let text: String?
        let label: String
        let isLanguage: Bool

        init(_ id: Int, icon: String? = nil, text: String? = nil, label: String,
             isLanguage: Bool = false) {
            self.id = id
            self.icon = icon
            self.text = text
            self.label = label
            self.isLanguage = isLanguage
        }
    }

    /// iOS 可執行的項目。10 在原皮膚是全選，iOS extension 沒有該 API，保留為常用語。
    static let selectable: [Definition] = [
        Definition(placeholder, text: "·", label: "空白佔位"),
        Definition(1, icon: "gearshape", label: "設定"),
        Definition(2, icon: "chevron.down", label: "收折鍵盤"),
        Definition(3, text: "米", label: "中英切換", isLanguage: true),
        Definition(5, icon: "heart.fill", label: "常用語"),
        Definition(7, icon: "curlybraces", label: "符號面板"),
        Definition(8, icon: "face.smiling", label: "Emoji"),
        Definition(9, icon: "textformat.123", label: "數字鍵盤"),
        Definition(10, icon: "heart.fill", label: "常用語"),
        Definition(13, icon: "doc.on.clipboard", label: "貼上"),
        Definition(16, icon: "arrow.left", label: "游標左移"),
        Definition(17, icon: "arrow.right", label: "游標右移"),
        Definition(26, text: "顏", label: "顏文字"),
        Definition(27, text: "ㄅ", label: "注音查碼"),
    ]

    static func definition(for id: Int) -> Definition? {
        selectable.first { $0.id == id }
            ?? (id == 29 ? definition(for: 9) : id == 30 ? definition(for: 7) : nil)
    }
}
