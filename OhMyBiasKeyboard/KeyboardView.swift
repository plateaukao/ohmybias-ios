import UIKit

enum KeyAction {
    case letter(String)        // a–z、,、.（中文模式進引擎組字）
    case symbol(String)        // 符號頁直接輸出
    case space
    case backspace
    case newline
    case toggleLanguage        // 中 ↔ 英
    case shift                 // 英文模式大寫
    case page(KeyboardView.Page)
    case zhuyinSymbol(String)
    case zhuyinTone(String)
    case zhuyinExit
    // sweetlime 滑動手勢動作
    case selectCandidateShortcut(Int)  // 次選/三選上屏（n/m 上滑）
    case lineStart                     // 游標移至句首（z 下滑）
    case lineEnd                       // 游標移至句尾（m 下滑）
    case pasteClipboard                // 貼上剪貼簿（v 下滑；需完整取用權限）
    case tab                           // Tab（b 下滑）
    case enterZhuyin                   // 跳轉注音查碼（Enter 上滑）
    // sweetlime 工具列動作
    case cursorLeft                    // 游標左移
    case cursorRight                   // 游標右移
    case dismissKeyboard               // 收折鍵盤
    case openSettings                  // 開啟容器 app 設定（ohmybias://）
}

/// 純程式碼鍵盤面板：字母頁／數字頁／符號頁／注音查碼頁。
final class KeyboardView: UIView {

    enum Page { case letters, numbers, symbols, zhuyin, numeric9, symbolPanel, emoji, kaomojis, phrases }

    var onKey: ((KeyAction) -> Void)?
    /// 地球鍵需綁 handleInputModeList — 由 controller 提供
    var onGlobeSetup: ((UIButton) -> Void)?

    var currentPage: Page = .letters
    var isEnglishMode = false
    var isShifted = false
    var needsInputModeSwitchKey = true
    /// Enter 鍵顯示文字（依 host app 的 returnKeyType：搜尋/前往/送出…）
    var returnKeyLabel = "⏎"

    private let rowsStack = UIStackView()
    private var keyButtons: [KeyButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        rowsStack.axis = .vertical
        rowsStack.distribution = .fillEqually
        rowsStack.spacing = 8
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowsStack)
        NSLayoutConstraint.activate([
            rowsStack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            rowsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        reloadKeys()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Layout definitions

    func reloadKeys() {
        rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        keyButtons.removeAll()
        panelView?.removeFromSuperview()
        panelView = nil
        rowsStack.isHidden = false
        let rows: [[KeySpec]]
        switch currentPage {
        case .letters: rows = letterRows()
        case .numbers: rows = numberRows()
        case .symbols: rows = symbolRows()
        case .zhuyin:  rows = zhuyinRows()
        case .numeric9: rows = numeric9Rows()
        case .symbolPanel:
            installPanel(CollectionData.symbols, fontSize: KeyboardTheme.panelSymbolFontSize); return
        case .emoji:
            installPanel(CollectionData.emojis, fontSize: KeyboardTheme.panelEmojiFontSize); return
        case .kaomojis:
            installPanel(CollectionData.kaomojis, fontSize: KeyboardTheme.panelKaomojiFontSize); return
        case .phrases:
            // ♥ 常用語面板 — 內容為 user_phrases.txt 自訂詞，點選直接上屏
            UserPhrases.shared.reload()
            installPanel([("常用語", UserPhrases.shared.allPhrases())],
                         fontSize: KeyboardTheme.panelKaomojiFontSize); return
        }
        // 真正的空白鍵（地球鍵也是 .space 動作，需排除）
        func isSpaceKey(_ spec: KeySpec) -> Bool {
            if case .space = spec.action { return !spec.isGlobe }
            return false
        }

        var previousUnitRef: KeyButton?  // 上一排的單位寬鍵（跨排對齊基準）
        for (rowIndex, row) in rows.enumerated() {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 5
            var buttons: [KeyButton] = []
            for spec in row {
                let b = makeKey(spec)
                rowStack.addArrangedSubview(b)
                buttons.append(b)
                keyButtons.append(b)
            }
            let unitRef = buttons.first { $0.spec.widthMultiplier == 1 && !isSpaceKey($0.spec) }
            // 先掛進視圖樹再 activate 約束 — 跨排約束需要 common ancestor
            rowsStack.addArrangedSubview(rowStack)

            if currentPage == .letters, rowIndex == 1, let ref = previousUnitRef {
                // 第二列（a–l）使用第一列的單鍵寬度。兩端各補半格，
                // 使按鍵中心相對首列左右各內縮半個鍵距。
                let leadingSpacer = UIView()
                let trailingSpacer = UIView()
                rowStack.insertArrangedSubview(leadingSpacer, at: 0)
                rowStack.addArrangedSubview(trailingSpacer)
                let spacerWidth = ref.widthAnchor.constraint(
                    equalTo: leadingSpacer.widthAnchor,
                    multiplier: 2,
                    constant: rowStack.spacing
                )
                spacerWidth.isActive = true
                trailingSpacer.widthAnchor.constraint(equalTo: leadingSpacer.widthAnchor).isActive = true
                rowStack.distribution = .fill
                for b in buttons {
                    b.widthAnchor.constraint(equalTo: ref.widthAnchor).isActive = true
                }
            } else if row.contains(where: isSpaceKey) {
                // 有空白鍵的排：其他鍵對齊「上一排」的單位寬（123/⏎ = shift 寬、
                // 逗號句號 = 字母鍵寬），空白鍵彈性吃掉全部剩餘寬度
                rowStack.distribution = .fill
                if let ref = previousUnitRef ?? unitRef {
                    for b in buttons where !isSpaceKey(b.spec) && b !== ref {
                        b.widthAnchor.constraint(equalTo: ref.widthAnchor,
                                                 multiplier: b.spec.widthMultiplier).isActive = true
                    }
                }
            } else {
                // 一般排：整排建完後統一套約束（含第一顆鍵 — 逐顆套會漏掉行首的加寬鍵）
                rowStack.distribution = .fillProportionally
                if let ref = unitRef {
                    for b in buttons where b !== ref {
                        b.widthAnchor.constraint(equalTo: ref.widthAnchor,
                                                 multiplier: b.spec.widthMultiplier).isActive = true
                    }
                }
            }
            if let ref = unitRef { previousUnitRef = ref }
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        if hitView is KeyButton || panelView != nil {
            return hitView
        }

        // 按鍵間距也屬於相鄰按鍵的可點區域；以距離中點平均劃分。
        let frames = keyButtons.map { ($0, $0.convert($0.bounds, to: self)) }
        guard let minX = frames.map({ $0.1.minX }).min(),
              let maxX = frames.map({ $0.1.maxX }).max(),
              let minY = frames.map({ $0.1.minY }).min(),
              let maxY = frames.map({ $0.1.maxY }).max(),
              point.x >= minX, point.x <= maxX, point.y >= minY, point.y <= maxY else {
            return hitView
        }
        return frames.min(by: { squaredDistance(from: point, to: $0.1) < squaredDistance(from: point, to: $1.1) })?.0
    }

    private func squaredDistance(from point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return dx * dx + dy * dy
    }

    struct KeySpec {
        let label: String
        let action: KeyAction
        var widthMultiplier: CGFloat = 1
        var isSpecial = false      // 灰色功能鍵底色
        var isGlobe = false
        var icon: String? = nil    // SF Symbol 名稱（設定時取代 label 顯示，單色線條風格）
        var swipeUp: SwipeData.Entry? = nil
        var swipeDown: SwipeData.Entry? = nil
        var longPress: LongPressData.Menu? = nil
    }

    /// 依 cskin 全域開關過濾滑動動作/角標
    private func swipeEntry(_ entry: SwipeData.Entry?, up: Bool) -> SwipeData.Entry? {
        let skin = SkinSettings.shared
        guard let entry, up ? skin.swipeUpEnabled : skin.swipeDownEnabled else { return nil }
        let showHint = up ? skin.showSwipeUpText : skin.showSwipeDownText
        return showHint ? entry : SwipeData.Entry(hint: nil, action: entry.action)
    }

    private func letterRows() -> [[KeySpec]] {
        let skin = SkinSettings.shared
        let r1 = "qwertyuiop".map { String($0) }
        let r2 = "asdfghjkl".map { String($0) }
        let r3 = "zxcvbnm".map { String($0) }
        func key(_ s: String) -> KeySpec {
            KeySpec(label: isEnglishMode && isShifted ? s.uppercased() : s, action: .letter(s),
                    swipeUp: swipeEntry(SwipeData.up[s], up: true),
                    swipeDown: swipeEntry(SwipeData.down[s], up: false),
                    longPress: skin.longPressEnabled ? LongPressData.letterMenu(s) : nil)
        }
        // 第三排前導鍵（sweetlime 版面）：中文模式＝小顆「英」切換鍵（shift 位置）、英文模式＝shift
        var row3: [KeySpec] = []
        if isEnglishMode {
            row3.append(KeySpec(label: "", action: .shift, isSpecial: true,
                                icon: isShifted ? "shift.fill" : "shift"))
        } else {
            row3.append(KeySpec(label: "英", action: .toggleLanguage, isSpecial: true))
        }
        row3 += r3.map(key)
        row3.append(KeySpec(label: "⌫", action: .backspace, widthMultiplier: 1.4, isSpecial: true))

        // 底列（sweetlime）：[123] [,] [大空白] [.] [⏎] — 123 縮至與 shift 同寬（單位鍵寬）、
        // ⏎ 同 ⌫(1.4)；逗號句號寬度依 spaceKeyLayout（'3' 空白最大），其餘全給空白鍵
        let punctWidth: CGFloat = skin.spaceKeyLayout == "1" ? 1.4 : (skin.spaceKeyLayout == "2" ? 1.2 : 1.0)
        let spaceWidth = 9.8 - 2.8 - punctWidth * 2 - (needsInputModeSwitchKey ? 1.0 : 0)
        let numericPage: Page = skin.keyboardLayout == "row" ? .numbers : .numeric9
        var row4: [KeySpec] = [
            KeySpec(label: "123", action: .page(numericPage), isSpecial: true),
        ]
        if needsInputModeSwitchKey {
            row4.append(KeySpec(label: "🌐", action: .space, widthMultiplier: 1.0, isSpecial: true, isGlobe: true))
        }
        row4.append(KeySpec(label: ",", action: .letter(","), widthMultiplier: punctWidth,
                            swipeUp: swipeEntry(SwipeData.up[","], up: true),
                            swipeDown: swipeEntry(SwipeData.down[","], up: false),
                            longPress: skin.longPressEnabled ? LongPressData.commaMenu : nil))
        row4.append(KeySpec(label: "", action: .space, widthMultiplier: spaceWidth,
                            swipeUp: swipeEntry(SwipeData.Entry(hint: nil, action: .toggleLanguage), up: true)))
        row4.append(KeySpec(label: isEnglishMode ? "." : "。", action: .letter("."), widthMultiplier: punctWidth,
                            swipeUp: swipeEntry(SwipeData.up["."], up: true),
                            swipeDown: swipeEntry(SwipeData.down["."], up: false),
                            longPress: skin.longPressEnabled ? LongPressData.periodMenu : nil))
        row4.append(KeySpec(label: returnKeyLabel, action: .newline, widthMultiplier: 1.4, isSpecial: true,
                            swipeUp: swipeEntry(SwipeData.Entry(hint: "ㄅ", action: .enterZhuyin), up: true),
                            swipeDown: swipeEntry(SwipeData.Entry(hint: nil, action: .newline), up: false)))

        return [r1.map(key), r2.map(key), row3, row4]
    }

    /// Row 數字/半形符號頁（sweetlime symbolic_row）：數字列＋常用半形符號、大空白
    private func numberRows() -> [[KeySpec]] {
        let r1 = "1234567890".map { String($0) }
        let r2 = ["-", "/", ":", ";", "(", ")", "$", "&", "@", "※"]
        let r3 = ["+", "*", ".", ",", "?", "!", "'"]
        var row3: [KeySpec] = [KeySpec(label: "#+=", action: .page(.symbols), widthMultiplier: 1.4, isSpecial: true)]
        row3 += r3.map { KeySpec(label: $0, action: .symbol($0)) }
        row3.append(KeySpec(label: "⌫", action: .backspace, widthMultiplier: 1.4, isSpecial: true))
        let row4: [KeySpec] = [
            KeySpec(label: "返回", action: .page(.letters), widthMultiplier: 1.4, isSpecial: true),
            KeySpec(label: "=", action: .symbol("=")),
            KeySpec(label: "空格", action: .space, widthMultiplier: 4.6),
            KeySpec(label: "\"", action: .symbol("\"")),
            KeySpec(label: returnKeyLabel, action: .newline, widthMultiplier: 1.5, isSpecial: true),
        ]
        return [r1.map { KeySpec(label: $0, action: .symbol($0)) }, r2.map { KeySpec(label: $0, action: .symbol($0)) }, row3, row4]
    }

    /// 全形符號頁（#+= 第二頁）
    private func symbolRows() -> [[KeySpec]] {
        let r1 = ["［", "］", "｛", "｝", "＃", "％", "＾", "＊", "＋", "＝"]
        let r2 = ["＿", "＼", "｜", "～", "＜", "＞", "《", "》", "€", "＆"]
        let r3 = ["『", "』", "【", "】", "〈", "〉", "・", "§"]
        var row3: [KeySpec] = [KeySpec(label: "123", action: .page(.numbers), widthMultiplier: 1.4, isSpecial: true)]
        row3 += r3.map { KeySpec(label: $0, action: .symbol($0)) }
        row3.append(KeySpec(label: "⌫", action: .backspace, widthMultiplier: 1.4, isSpecial: true))
        let row4: [KeySpec] = [
            KeySpec(label: "返回", action: .page(.letters), widthMultiplier: 1.5, isSpecial: true),
            KeySpec(label: "空格", action: .space, widthMultiplier: 5.5),
            KeySpec(label: returnKeyLabel, action: .newline, widthMultiplier: 1.8, isSpecial: true),
        ]
        return [r1.map { KeySpec(label: $0, action: .symbol($0)) }, r2.map { KeySpec(label: $0, action: .symbol($0)) }, row3, row4]
    }

    /// 九宮格數字鍵盤（sweetlime 預設 keyboardLayout 'panel'）：
    /// 左欄符號、中間數字九宮格、右欄功能鍵，底列 [返回][#+=][0][空白][⏎]
    private func numeric9Rows() -> [[KeySpec]] {
        func sym(_ s: String) -> KeySpec { KeySpec(label: s, action: .symbol(s), isSpecial: true) }
        func digit(_ d: String) -> KeySpec { KeySpec(label: d, action: .symbol(d)) }
        let r1: [KeySpec] = [sym("@"), digit("1"), digit("2"), digit("3"),
                             KeySpec(label: "⌫", action: .backspace, isSpecial: true)]
        let r2: [KeySpec] = [sym("%"), digit("4"), digit("5"), digit("6"),
                             KeySpec(label: ".", action: .symbol("."), isSpecial: true)]
        let r3: [KeySpec] = [sym("-"), digit("7"), digit("8"), digit("9"), sym("+")]
        let r4: [KeySpec] = [
            KeySpec(label: "返回", action: .page(.letters), isSpecial: true),
            KeySpec(label: "#+=", action: .page(.numbers), isSpecial: true),
            digit("0"),
            KeySpec(label: "空格", action: .space),
            KeySpec(label: returnKeyLabel, action: .newline, isSpecial: true),
        ]
        return [r1, r2, r3, r4]
    }

    // MARK: - 分類面板頁（符號/Emoji/顏文字）

    private var panelView: CollectionPanelView?

    private func installPanel(_ sections: [(String, [String])], fontSize: CGFloat) {
        guard MemoryBudget.canAfford(MemoryBudget.collectionPanel) else { return }
        rowsStack.isHidden = true
        let panel = CollectionPanelView(sections: sections, itemFontSize: fontSize)
        panel.onInsert = { [weak self] text in self?.onKey?(.symbol(text)) }
        panel.onBack = { [weak self] in self?.onKey?(.page(.letters)) }
        panel.onBackspace = { [weak self] in self?.onKey?(.backspace) }
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: topAnchor),
            panel.leadingAnchor.constraint(equalTo: leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        panelView = panel
    }

    /// 標準注音鍵盤排列（對應 qwerty 位置），聲調鍵混排於其中
    private func zhuyinRows() -> [[KeySpec]] {
        let tones: Set<String> = ["ˊ", "ˇ", "ˋ", "˙"]
        func zy(_ s: String) -> KeySpec {
            tones.contains(s) ? KeySpec(label: s, action: .zhuyinTone(s))
                              : KeySpec(label: s, action: .zhuyinSymbol(s))
        }
        let r1 = ["ㄅ", "ㄉ", "ˇ", "ˋ", "ㄓ", "ˊ", "˙", "ㄚ", "ㄞ", "ㄢ"].map(zy)
        let r2 = ["ㄆ", "ㄊ", "ㄍ", "ㄐ", "ㄔ", "ㄗ", "ㄧ", "ㄛ", "ㄟ", "ㄣ"].map(zy)
        let r3 = ["ㄇ", "ㄋ", "ㄎ", "ㄑ", "ㄕ", "ㄘ", "ㄨ", "ㄜ", "ㄠ", "ㄤ"].map(zy)
        var r4 = ["ㄈ", "ㄌ", "ㄏ", "ㄒ", "ㄖ", "ㄙ", "ㄩ", "ㄝ", "ㄡ", "ㄥ"].map(zy)
        r4.append(zy("ㄦ"))
        let row5: [KeySpec] = [
            KeySpec(label: "退出", action: .zhuyinExit, widthMultiplier: 1.5, isSpecial: true),
            KeySpec(label: "空白（一聲）", action: .space, widthMultiplier: 5.5),
            KeySpec(label: "⌫", action: .backspace, widthMultiplier: 1.8, isSpecial: true),
        ]
        return [r1, r2, r3, r4, row5]
    }

    // MARK: - Key construction

    private func makeKey(_ spec: KeySpec) -> KeyButton {
        let b = KeyButton(spec: spec)
        if spec.isGlobe {
            onGlobeSetup?(b)
        } else {
            b.onAction = { [weak self] action in self?.onKey?(action) }
            if spec.longPress != nil {
                b.onLongPressBegan = { [weak self] btn in self?.showPopup(for: btn) }
                b.onLongPressMoved = { [weak self] btn, pt in self?.movePopupSelection(from: btn, point: pt) }
                b.onLongPressEnded = { [weak self] btn, commit in self?.endPopup(from: btn, commit: commit) }
            }
        }
        return b
    }

    // MARK: - Long-press popup

    private var activePopup: LongPressPopup?

    private func showPopup(for button: KeyButton) {
        guard let menu = button.spec.longPress else { return }
        endPopup(from: button, commit: false)
        let popup = LongPressPopup(options: menu.options, defaultIndex: menu.defaultIndex)
        let keyFrame = button.convert(button.bounds, to: self)
        var x = keyFrame.midX - popup.bounds.width / 2
        x = max(4, min(bounds.width - popup.bounds.width - 4, x))
        popup.frame.origin = CGPoint(x: x, y: keyFrame.minY - popup.bounds.height - 6)
        addSubview(popup)
        activePopup = popup
    }

    private func movePopupSelection(from button: KeyButton, point: CGPoint) {
        guard let popup = activePopup else { return }
        let inPopup = button.convert(point, to: popup)
        popup.updateSelection(forX: inPopup.x)
    }

    private func endPopup(from button: KeyButton, commit: Bool) {
        guard let popup = activePopup else { return }
        if commit, let menu = button.spec.longPress {
            let option = menu.options[popup.selectedIndex]
            onKey?(.symbol(LongPressData.resolve(option)))
        }
        popup.removeFromSuperview()
        activePopup = nil
    }
}

/// 圓角按鍵 — sweetlime 線稿風：一般鍵描邊、功能鍵填色（深色模式反白）。
/// 自行處理 touch：點按＝主動作、垂直滑動＝上滑/下滑動作、⌫ 長按連刪。
final class KeyButton: UIButton {
    let spec: KeyboardView.KeySpec
    var onAction: ((KeyAction) -> Void)?
    var onLongPressBegan: ((KeyButton) -> Void)?
    var onLongPressMoved: ((KeyButton, CGPoint) -> Void)?
    var onLongPressEnded: ((KeyButton, Bool) -> Void)?

    /// 滑動觸發距離（pt）
    private static let swipeThreshold: CGFloat = 25

    private var touchStartPoint: CGPoint?
    private var repeatTimer: Timer?
    private var longPressTimer: Timer?
    private var isInLongPress = false
    /// 空白鍵水平拖曳移動游標（同系統鍵盤手感）
    private var isDraggingCursor = false
    private var dragAnchorX: CGFloat = 0
    private static let cursorDragStep: CGFloat = 9

    init(spec: KeyboardView.KeySpec) {
        self.spec = spec
        super.init(frame: .zero)
        if let icon = spec.icon {
            // SF Symbol 鍵面（如 shift/shift.fill）— 單色，與其他圖示同風格
            let config = UIImage.SymbolConfiguration(pointSize: KeyboardTheme.systemFontSize + 2, weight: .regular)
            setImage(UIImage(systemName: icon, withConfiguration: config), for: .normal)
            tintColor = spec.isSpecial ? KeyboardTheme.textSystem : KeyboardTheme.textMain
            accessibilityLabel = icon
        } else {
            setTitle(spec.label, for: .normal)
            let size: CGFloat = spec.label.count > 1
                ? KeyboardTheme.systemFontSize
                : (spec.isSpecial ? KeyboardTheme.systemFontSize + 4 : KeyboardTheme.alphabetFontSize)
            titleLabel?.font = .systemFont(ofSize: size)
            setTitleColor(spec.isSpecial ? KeyboardTheme.textSystem : KeyboardTheme.textMain, for: .normal)
        }
        layer.cornerRadius = KeyboardTheme.cornerRadius
        layer.borderWidth = KeyboardTheme.borderWidth
        addHintLabels()
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 鍵帽角標：上滑符號置頂中、下滑符號置右下（同 sweetlime 版面）
    private func addHintLabels() {
        if let hint = spec.swipeUp?.hint {
            let l = hintLabel(hint)
            NSLayoutConstraint.activate([
                l.centerXAnchor.constraint(equalTo: centerXAnchor),
                l.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            ])
        }
        if let hint = spec.swipeDown?.hint {
            let l = hintLabel(hint)
            NSLayoutConstraint.activate([
                l.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                l.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            ])
        }
    }

    private func hintLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: KeyboardTheme.swipeHintFontSize)
        l.textColor = KeyboardTheme.textSub
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isUserInteractionEnabled = false
        addSubview(l)
        return l
    }

    private func applyColors() {
        if spec.isSpecial {
            backgroundColor = isHighlighted ? KeyboardTheme.keySystemHighlight : KeyboardTheme.keySystem
            layer.borderColor = KeyboardTheme.systemBorder.resolvedColor(with: traitCollection).cgColor
        } else {
            backgroundColor = isHighlighted ? KeyboardTheme.keyNormalHighlight : KeyboardTheme.keyNormal
            layer.borderColor = KeyboardTheme.border.resolvedColor(with: traitCollection).cgColor
        }
    }

    override var isHighlighted: Bool {
        didSet { applyColors() }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyColors()  // CGColor 不會自動跟隨深淺色
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard onAction != nil else { return }  // 地球鍵走 UIControl 路徑
        isHighlighted = true
        isInLongPress = false
        touchStartPoint = touches.first?.location(in: self)
        if case .backspace = spec.action {
            onAction?(.backspace)
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                    self?.onAction?(.backspace)
                }
            }
        }
        if spec.longPress != nil {
            longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.isInLongPress = true
                self.onLongPressBegan?(self)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard onAction != nil, let point = touches.first?.location(in: self) else { return }
        if isInLongPress {
            onLongPressMoved?(self, point)
            return
        }
        // 空白鍵：水平拖曳 → 逐步移動游標
        if case .space = spec.action, let start = touchStartPoint {
            let dx = point.x - start.x
            if !isDraggingCursor, abs(dx) > 15, abs(dx) > abs(point.y - start.y) {
                isDraggingCursor = true
                stopLongPressTimer()
                dragAnchorX = point.x
            }
            if isDraggingCursor {
                while point.x - dragAnchorX > Self.cursorDragStep {
                    onAction?(.cursorRight); dragAnchorX += Self.cursorDragStep
                }
                while dragAnchorX - point.x > Self.cursorDragStep {
                    onAction?(.cursorLeft); dragAnchorX -= Self.cursorDragStep
                }
                return
            }
        }
        // 開始滑動即取消長按等待
        if let start = touchStartPoint, hypot(point.x - start.x, point.y - start.y) > 12 {
            stopLongPressTimer()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard onAction != nil else { return }
        isHighlighted = false
        stopRepeat()
        stopLongPressTimer()
        if isDraggingCursor {
            isDraggingCursor = false
            touchStartPoint = nil
            return  // 拖曳游標結束，不輸出空白
        }
        if isInLongPress {
            isInLongPress = false
            touchStartPoint = nil
            onLongPressEnded?(self, true)
            return
        }
        if case .backspace = spec.action { return }  // 已在 touchDown 觸發
        guard let start = touchStartPoint, let end = touches.first?.location(in: self) else { return }
        touchStartPoint = nil
        let dx = end.x - start.x, dy = end.y - start.y
        if abs(dy) > Self.swipeThreshold, abs(dy) > abs(dx) {
            if dy < 0, let entry = spec.swipeUp { onAction?(entry.action); return }
            if dy > 0, let entry = spec.swipeDown { onAction?(entry.action); return }
        }
        // 一般點按：允許少量滑出（同系統鍵盤手感）
        if bounds.insetBy(dx: -20, dy: -20).contains(end) {
            onAction?(spec.action)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        isHighlighted = false
        stopRepeat()
        stopLongPressTimer()
        isDraggingCursor = false
        if isInLongPress {
            isInLongPress = false
            onLongPressEnded?(self, false)
        }
        touchStartPoint = nil
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    private func stopLongPressTimer() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }
}
