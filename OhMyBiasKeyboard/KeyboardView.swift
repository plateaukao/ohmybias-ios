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
    case toggleToolbarPage(KeyboardView.Page)
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
    case openSettings                  // 展開 ⚙ 指令面板
}

/// 純程式碼鍵盤面板：字母頁／數字頁／符號頁／注音查碼頁。
final class KeyboardView: UIView {

    enum Page { case letters, numbers, symbols, zhuyin, numeric9, symbolPanel, emoji, kaomojis, phrases }

    var onKey: ((KeyAction) -> Void)?
    /// 地球鍵需綁 handleInputModeList — 由 controller 提供
    var onGlobeSetup: ((UIButton) -> Void)?
    /// 面板頁記憶體不足時先呼叫此鉤子把所有可重建快取放掉（反查表、注音表、字形快取），再重試一次
    var onPanelMemoryRelief: (() -> Void)?
    /// 釋放後仍裝不了面板：已回退到字母頁 — controller 據此顯示提示
    var onPanelUnavailable: (() -> Void)?

    var currentPage: Page = .letters
    /// 中英切換改變第三排前導鍵（英/⇧）與標點 — 變更時就地重建，
    /// 不再依賴 viewWillAppear 的無條件 reloadKeys 事後修正
    var isEnglishMode = false {
        didSet { if isEnglishMode != oldValue { reloadKeys() } }
    }
    var isShifted = false
    var needsInputModeSwitchKey = true
    /// Enter 鍵顯示文字（依 host app 的 returnKeyType：搜尋/前往/送出…）
    var returnKeyLabel = "⏎"

    private let rowsStack = UIStackView()
    /// 鍵面頂端留白（候選列與第一排鍵之間的縫）
    static let topMargin: CGFloat = 6
    private var keyButtons: [KeyButton] = []
    private var pageBeforeToolbarToggle: Page?
    /// 建鍵時的皮膚世代 — 皮膚重載後才需要重建 KeySpec（滑動開關/版面選項）
    private var builtSkinGeneration = -1
    /// 建鍵時「中文模式大寫字母」偏好值 — 在容器 app 改過後回鍵盤要重建鍵面
    private var builtUppercaseLetters = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        rowsStack.axis = .vertical
        rowsStack.distribution = .fillEqually
        rowsStack.spacing = 8
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowsStack)
        NSLayoutConstraint.activate([
            rowsStack.topAnchor.constraint(equalTo: topAnchor, constant: Self.topMargin),
            rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            rowsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        reloadKeys()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Layout definitions

    func showPage(_ page: Page) {
        if currentPage == page && pageBeforeToolbarToggle == nil { return }  // 同頁免重建
        currentPage = page
        pageBeforeToolbarToggle = nil
        reloadKeys()
    }

    /// viewWillAppear 每次鍵盤出現都會呼叫 — 只有鍵面實際會變（🌐 鍵有無、
    /// Enter 標籤、皮膚重載）才整面重建（取法 sweetlime initOnStartInput 的短路）
    func syncSessionState(needsSwitchKey: Bool, returnLabel: String) {
        if needsInputModeSwitchKey == needsSwitchKey && returnKeyLabel == returnLabel
            && builtSkinGeneration == SkinSettings.shared.generation
            && builtUppercaseLetters == OhMyBiasPrefs.uppercaseLettersInChinese
            && currentPage != .phrases {  // 常用語可能在容器 app 被改過 — 回鍵盤時重讀
            return
        }
        needsInputModeSwitchKey = needsSwitchKey
        returnKeyLabel = returnLabel
        reloadKeys()
    }

    /// 收鍵盤／記憶體警告時呼叫 — 拆掉面板並回到字母頁，讓 cell 與圖層釋放。
    /// 面板頁不會跨 session 保留（本來每次回鍵盤也都是從字母頁開始）
    func releasePanels() {
        guard panelView != nil || currentPage != .letters else { return }
        currentPage = .letters
        pageBeforeToolbarToggle = nil
        reloadKeys()
    }

    func toggleToolbarPage(_ page: Page) {
        if currentPage == page {
            currentPage = pageBeforeToolbarToggle ?? .letters
            pageBeforeToolbarToggle = nil
        } else {
            pageBeforeToolbarToggle = currentPage
            currentPage = page
        }
        reloadKeys()
    }

    func reloadKeys() {
        builtSkinGeneration = SkinSettings.shared.generation
        builtUppercaseLetters = OhMyBiasPrefs.uppercaseLettersInChinese
        rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        keyButtons.removeAll()
        if panelView != nil {
            panelView?.removeFromSuperview()
            panelView = nil
            // 面板拆掉後 CoreText 快取裡的 emoji 字形已沒人用 — 現在清才會真的退記憶體
            CoreTextGlyphCache.drain()
        }
        rowsStack.isHidden = false
        let rows: [[KeySpec]]
        switch currentPage {
        case .letters: rows = letterRows()
        case .numbers: rows = numberRows()
        case .symbols: rows = symbolRows()
        case .zhuyin:  rows = zhuyinRows()
        case .numeric9: rows = numeric9Rows()
        case .symbolPanel, .emoji, .kaomojis, .phrases:
            if installPanel(for: currentPage) { return }
            // 記憶體不足裝不了面板 — 回退字母頁，絕不留空白鍵盤
            currentPage = .letters
            pageBeforeToolbarToggle = nil
            onPanelUnavailable?()
            rows = letterRows()
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

    /// 頂端 6pt 留白是否讓給上方的候選列（有候選時，縫裡起手要能捲候選）
    var yieldTopMargin: (() -> Bool)?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        if hitView is KeyButton || panelView != nil {
            return hitView
        }
        if point.y < Self.topMargin, hitView != nil, yieldTopMargin?() == true {
            return nil  // 讓父視圖繼續測到 CandidateBar（其 point(inside:) 向下延伸接手）
        }

        // 按鍵間距與鍵盤外緣（左右 3pt、上下 6pt）也屬於最近按鍵的可點區域；
        // hitView 非 nil 即點在本視圖內，整面都轉給最近的鍵，不留死角。
        guard hitView != nil else { return nil }
        let frames = keyButtons.map { ($0, $0.convert($0.bounds, to: self)) }
        return frames.min(by: { squaredDistance(from: point, to: $0.1) < squaredDistance(from: point, to: $1.1) })?.0
            ?? hitView
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
        // 鍵面大寫：英文模式看 shift；中文模式看偏好（字根表慣用大寫）。action 一律小寫碼
        let uppercase = isEnglishMode ? isShifted : OhMyBiasPrefs.uppercaseLettersInChinese
        func key(_ s: String) -> KeySpec {
            KeySpec(label: uppercase ? s.uppercased() : s, action: .letter(s),
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

        // 底列（sweetlime）：[123] [🌐] [,] [大空白] [.] [⏎] — 123 縮至與 shift 同寬（單位鍵寬）、
        // ⏎ 同 ⌫(1.4)。工具列已有 123（按鈕 ID 9/29）時省略底列 123 鍵。
        // 空白鍵永遠優先：逗號句號固定標準鍵寬（不採皮膚 spaceKeyLayout 放大值），剩餘全給空白鍵
        let show123Key = !skin.toolbarButtons.contains { $0 == 9 || $0 == 29 }
        let numericPage: Page = skin.keyboardLayout == "row" ? .numbers : .numeric9
        var row4: [KeySpec] = []
        if show123Key {
            row4.append(KeySpec(label: "123", action: .page(numericPage), isSpecial: true))
        }
        if needsInputModeSwitchKey {
            row4.append(KeySpec(label: "🌐", action: .space, widthMultiplier: 1.0, isSpecial: true, isGlobe: true))
        }
        row4.append(KeySpec(label: ",", action: .letter(","),
                            swipeUp: swipeEntry(SwipeData.up[","], up: true),
                            swipeDown: swipeEntry(SwipeData.down[","], up: false),
                            longPress: skin.longPressEnabled ? LongPressData.commaMenu : nil))
        row4.append(KeySpec(label: "", action: .space,
                            swipeUp: swipeEntry(SwipeData.Entry(hint: nil, action: .toggleLanguage), up: true)))
        row4.append(KeySpec(label: isEnglishMode ? "." : "。", action: .letter("."),
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

    /// 依面板頁取內容並嘗試安裝；記憶體不足時回傳 false（不動 rowsStack）。
    /// 分類內容一律以 closure 傳入 — 點到該分類才取值（見 CollectionPanelView）
    private func installPanel(for page: Page) -> Bool {
        switch page {
        case .symbolPanel:
            return installPanel(lazySections(CollectionData.symbols),
                                fontSize: KeyboardTheme.panelSymbolFontSize)
        case .emoji:
            // 「常用」分類 = 最近使用紀錄，排在「表情」前；沒紀錄就不顯示
            let recent = RecentEmojis.shared.all()
            var sections = lazySections(CollectionData.emojis)
            if !recent.isEmpty { sections.insert(("常用", { recent }), at: 0) }
            return installPanel(sections, fontSize: KeyboardTheme.panelEmojiFontSize, recordRecent: true)
        case .kaomojis:
            return installPanel(lazySections(CollectionData.kaomojis),
                                fontSize: KeyboardTheme.panelKaomojiFontSize)
        case .phrases:
            // ♥ 常用語面板 — 內容為 user_phrases.txt 自訂詞，點選直接上屏
            return installPanel([("常用語", {
                UserPhrases.shared.reload()
                return UserPhrases.shared.allPhrases()
            })], fontSize: KeyboardTheme.panelKaomojiFontSize)
        default:
            return false
        }
    }

    /// 靜態分類表 → 延後取值的分類表（索引綁定，取值時才碰該分類的陣列）
    private func lazySections(_ data: [(String, [String])]) -> [(String, () -> [String])] {
        data.indices.map { i in (data[i].0, { data[i].1 }) }
    }

    private func installPanel(_ sections: [(String, () -> [String])], fontSize: CGFloat, recordRecent: Bool = false) -> Bool {
        if !MemoryBudget.canAfford(MemoryBudget.collectionPanel) {
            onPanelMemoryRelief?()
            guard MemoryBudget.canAfford(MemoryBudget.collectionPanel) else { return false }
        }
        rowsStack.isHidden = true
        let panel = CollectionPanelView(sections: sections, itemFontSize: fontSize)
        panel.onInsert = { [weak self] text in
            if recordRecent { RecentEmojis.shared.record(text) }
            self?.onKey?(.symbol(text))
        }
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
        return true
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
        // 邊框寬/色都分平時與按下兩套（皮膚未定義按下值時鏈回平時值）— 皮膚淺/深邊框寬可能不同
        layer.borderWidth = isHighlighted ? KeyboardTheme.borderWidthHighlight(for: traitCollection)
                                          : KeyboardTheme.borderWidth(for: traitCollection)
        if spec.isSpecial {
            backgroundColor = isHighlighted ? KeyboardTheme.keySystemHighlight : KeyboardTheme.keySystem
            let bd = isHighlighted ? KeyboardTheme.systemBorderHighlight : KeyboardTheme.systemBorder
            layer.borderColor = bd.resolvedColor(with: traitCollection).cgColor
        } else {
            backgroundColor = isHighlighted ? KeyboardTheme.keyNormalHighlight : KeyboardTheme.keyNormal
            let bd = isHighlighted ? KeyboardTheme.borderHighlight : KeyboardTheme.border
            layer.borderColor = bd.resolvedColor(with: traitCollection).cgColor
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
            // 連刪節奏同 sweetlime（400ms 起跑、50ms/字 = 20 字/秒）
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                    self?.onAction?(.backspace)
                }
            }
        }
        if spec.longPress != nil {
            longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
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
