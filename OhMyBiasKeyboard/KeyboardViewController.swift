import UIKit

/// iOS 鍵盤 extension 主控制器 — InputEngine 的 iOS delegate 實作。
/// 對應 macOS 版的 InputController：鍵盤事件 → InputEngine → delegate 回呼 → UI。
final class KeyboardViewController: UIInputViewController {

    private var engine: InputEngine!
    private let candidateBar = CandidateBar()
    private let keyboardView = KeyboardView()
    private let toastLabel = UILabel()
    private var toastWorkItem: DispatchWorkItem?
    private var heightConstraint: NSLayoutConstraint?

    /// 候選列目前顯示的是聯想詞（composing 為空時點選直接送出）
    private var showingSuggestions = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        SkinSettings.shared.reload()  // 讀取匯入的 cskin 設定（工具列/配色/字級/版面）
        engine = InputEngine()
        engine.delegate = self
        engine.loadTable()
        engine.scheduleBackgroundTasks()
        // 還原上次使用的語言模式（EN/中文）
        engine.setEnglishMode(OhMyBiasPrefs.lastEnglishMode)
        keyboardView.isEnglishMode = engine.isEnglishMode
        setUpViews()
        refreshIdleBar()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyToolbarBackground()
        // 只有鍵面實際會變才重建按鍵（syncSessionState 內比對短路）
        keyboardView.syncSessionState(
            needsSwitchKey: needsInputModeSwitchKey,
            returnLabel: Self.returnLabel(for: textDocumentProxy.returnKeyType)
        )
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 收鍵盤時把未寫入的字頻紀錄落盤 — extension 被殺也不掉學習資料
        engine.freqTracker.flushAll()
    }

    // 深淺色：完全跟隨繼承的 trait（extension window 會即時跟系統外觀），
    // 由 UIKit 自動重解所有動態色。兩個看似可用的外觀來源實測都不可靠，絕不可用：
    // - UIScreen.main.traitCollection：extension 行程裡不跟系統更新（切深色後仍
    //   回報淺色）— 舊版在色彩 provider 內讀它，正是「切深淺色偶發卡舊主題」的根因。
    // - textDocumentProxy.keyboardAppearance：host 給的快照會過期（Spotlight 深色
    //   模式下仍回報 .light；系統鍵盤同場景實測照樣顯示深色）— 據此設
    //   overrideUserInterfaceStyle 會把鍵盤釘在錯誤主題。

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyToolbarBackground()
    }

    /// Enter 鍵依 host app 的 returnKeyType 顯示（搜尋/前往/送出…）
    private static func returnLabel(for type: UIReturnKeyType?) -> String {
        switch type {
        case .search: return "搜尋"
        case .go: return "前往"
        case .send: return "送出"
        case .done: return "完成"
        case .next: return "下一個"
        case .join: return "加入"
        case .continue: return "繼續"
        default: return "⏎"
        }
    }

    override func updateViewConstraints() {
        super.updateViewConstraints()
        let isLandscape = view.bounds.width > 500
        let height = CGFloat(isLandscape ? 180 : 224) * CGFloat(OhMyBiasPrefs.keyboardHeightScale)
            + CandidateBar.barHeight
        if let c = heightConstraint {
            c.constant = height
        } else {
            let c = view.heightAnchor.constraint(equalToConstant: height)
            c.priority = .init(999)
            c.isActive = true
            heightConstraint = c
        }
    }

    private func setUpViews() {
        applyToolbarBackground()
        candidateBar.translatesAutoresizingMaskIntoConstraints = false
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(candidateBar)
        view.addSubview(keyboardView)
        NSLayoutConstraint.activate([
            candidateBar.topAnchor.constraint(equalTo: view.topAnchor),
            candidateBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            candidateBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            candidateBar.heightAnchor.constraint(equalToConstant: CandidateBar.barHeight),
            keyboardView.topAnchor.constraint(equalTo: candidateBar.bottomAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        candidateBar.onSelect = { [weak self] idx in self?.didSelectCandidate(at: idx) }
        candidateBar.onToolbarKey = { [weak self] action in self?.handleKey(action) }
        keyboardView.onKey = { [weak self] action in self?.handleKey(action) }
        keyboardView.onGlobeSetup = { [weak self] button in
            guard let self else { return }
            button.addTarget(self, action: #selector(self.handleInputModeList(from:with:)), for: .allTouchEvents)
        }

        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        toastLabel.font = .systemFont(ofSize: 20, weight: .medium)
        toastLabel.textColor = .white
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        toastLabel.layer.cornerRadius = 10
        toastLabel.layer.masksToBounds = true
        toastLabel.textAlignment = .center
        toastLabel.numberOfLines = 0
        toastLabel.isHidden = true
        view.addSubview(toastLabel)
        NSLayoutConstraint.activate([
            toastLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastLabel.centerYAnchor.constraint(equalTo: keyboardView.centerYAnchor),
            toastLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32),
        ])
    }

    private func applyToolbarBackground() {
        // iOS 27 液態玻璃：背板交給系統玻璃，不自畫鍵盤/工具列背景 —
        // 鍵面與內容色已在 KeyboardTheme 壓成不透明，玻璃只透出鍵外空隙
        if KeyboardTheme.glassHost {
            view.backgroundColor = .clear
            inputView?.backgroundColor = .clear
            return
        }
        // iOS 將 extension 的 view 包在稍後才掛載的、有上方圓角的 input-host；
        // 從 extension view 一路著色至 window，避免露出系統預設鍵盤背景。
        let color = KeyboardTheme.toolbarBackground
        view.backgroundColor = color
        inputView?.backgroundColor = color
        var container = view.superview
        while let current = container {
            current.backgroundColor = color
            if current === view.window { break }
            container = current.superview
        }
        view.window?.backgroundColor = color
    }

    // MARK: - Key handling

    private func handleKey(_ action: KeyAction) {
        if OhMyBiasPrefs.hapticFeedback {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        switch action {
        case .letter(let ch):
            handleLetterKey(ch)
        case .space:
            handleSpaceKey()
        case .backspace:
            handleBackspaceKey()
        case .newline:
            handleReturnKey()
        case .symbol(let s):
            // 符號頁直接送出（不經引擎組字）
            engine.handleEscape()
            textDocumentProxy.insertText(s)
        case .toggleLanguage:
            engine.toggleEnglishMode()
            keyboardView.isEnglishMode = engine.isEnglishMode
            keyboardView.showPage(.letters)  // 從工具列切換時回到字母頁
            OhMyBiasPrefs.lastEnglishMode = engine.isEnglishMode
            refreshIdleBar()
        case .page(let page):
            keyboardView.showPage(page)
        case .toggleToolbarPage(let page):
            keyboardView.toggleToolbarPage(page)
        case .shift:
            keyboardView.isShifted.toggle()
            keyboardView.reloadKeys()
        case .zhuyinSymbol(let zy):
            engine.handleZhuyinSymbol(zy)
        case .zhuyinTone(let tone):
            engine.handleZhuyinTone(tone)
        case .zhuyinExit:
            engine.exitZhuyinMode()
            keyboardView.currentPage = .letters
            keyboardView.reloadKeys()
        case .selectCandidateShortcut(let idx):
            // 次選/三選上屏（sweetlime n/m 上滑）— 無候選時不動作
            if engine.currentCandidates.count > idx { didSelectCandidate(at: idx) }
        case .lineStart:
            let count = textDocumentProxy.documentContextBeforeInput?.count ?? 0
            if count > 0 { textDocumentProxy.adjustTextPosition(byCharacterOffset: -count) }
        case .lineEnd:
            let count = textDocumentProxy.documentContextAfterInput?.count ?? 0
            if count > 0 { textDocumentProxy.adjustTextPosition(byCharacterOffset: count) }
        case .pasteClipboard:
            engine.handleEscape()
            guard hasFullAccess else {
                showToast("請在鍵盤設定啟用完整取用權限", duration: 1.5)
                return
            }
            if let text = ClipboardProcessor.plainText(), !text.isEmpty {
                textDocumentProxy.insertText(text)
            } else {
                showToast("剪貼簿為空", duration: 1.2)
            }
        case .tab:
            engine.handleEscape()
            textDocumentProxy.insertText("\t")
        case .enterZhuyin:
            engine.switchToMode("zh")
            keyboardView.showPage(.zhuyin)
        case .cursorLeft:
            textDocumentProxy.adjustTextPosition(byCharacterOffset: -1)
        case .cursorRight:
            textDocumentProxy.adjustTextPosition(byCharacterOffset: 1)
        case .dismissKeyboard:
            dismissKeyboard()
        case .openSettings:
            openContainerApp()
        }
    }

    /// 開啟容器 app 的設定畫面。鍵盤 extension 編譯期擋掉 UIApplication.shared，
    /// 但 responder chain 上的 UIApplication 實體存在 — 以 objc selector 呼叫 openURL:。
    /// （extensionContext.open 對鍵盤 extension 常不回呼 completion，只當備援）
    private func openContainerApp() {
        guard let url = URL(string: "ohmybias://settings") else { return }
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self.next
        while let r = responder {
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                return
            }
            responder = r.next
        }
        extensionContext?.open(url)
        showToast("無法開啟設定 — 請從主畫面開啟 OhMyBias 米", duration: 1.5)
    }

    private func handleLetterKey(_ ch: String) {
        if engine.isEnglishMode {
            let out = keyboardView.isShifted ? ch.uppercased() : ch
            if keyboardView.isShifted { keyboardView.isShifted = false; keyboardView.reloadKeys() }
            textDocumentProxy.insertText(out)
            return
        }
        if engine.isPinyinMode {
            if let d = Int(ch), (1...5).contains(d) { engine.handlePinyinTone(d) }
            else { engine.handlePinyinLetter(ch) }
            return
        }
        // VRSF 快選：v/r/s/f 選第 2–5 個候選（碼不可延伸時）
        if engine.handleVRSF(ch) { return }
        engine.handleLetter(ch)
    }

    private func handleSpaceKey() {
        if engine.isEnglishMode { textDocumentProxy.insertText(" "); return }
        if engine.isPinyinMode { engine.handlePinyinSpace(); return }
        if engine.isZhuyinMode { engine.handleZhuyinSpace(); return }
        if engine.composing.isEmpty && !showingSuggestions {
            textDocumentProxy.insertText(" ")
            return
        }
        if engine.composing.isEmpty && showingSuggestions {
            // 聯想詞顯示中按空白 → 清除聯想、輸出空白
            clearSuggestions()
            textDocumentProxy.insertText(" ")
            return
        }
        engine.handleSpace()
    }

    private func handleBackspaceKey() {
        if engine.isEnglishMode { textDocumentProxy.deleteBackward(); return }
        if engine.isPinyinMode { engine.handlePinyinBackspace(); return }
        if showingSuggestions { clearSuggestions() }
        engine.handleBackspace()
    }

    private func handleReturnKey() {
        if engine.isPinyinMode { engine.exitPinyinMode(); return }
        if !engine.composing.isEmpty || engine.isInSpecialMode {
            engine.handleEnter()
            return
        }
        if showingSuggestions { clearSuggestions() }
        textDocumentProxy.insertText("\n")
    }

    private func didSelectCandidate(at index: Int) {
        if OhMyBiasPrefs.hapticFeedback {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        if engine.isPinyinMode { engine.selectPinyinCandidate(at: index); return }
        engine.selectCandidate(at: index)
    }

    private func clearSuggestions() {
        showingSuggestions = false
        engine.clearCandidates()
        refreshIdleBar()
    }

    private func refreshIdleBar() {
        candidateBar.setComposing("")
        candidateBar.setCandidates([], suggestions: false)
        candidateBar.setEnglishMode(engine.isEnglishMode)
    }

    // MARK: - Zhuyin page sync

    private func syncPageWithEngine() {
        let wantZhuyin = engine.isZhuyinMode
        if wantZhuyin && keyboardView.currentPage != .zhuyin {
            keyboardView.currentPage = .zhuyin
            keyboardView.reloadKeys()
        } else if !wantZhuyin && keyboardView.currentPage == .zhuyin {
            keyboardView.currentPage = .letters
            keyboardView.reloadKeys()
        }
    }
}

// MARK: - InputEngineDelegate

extension KeyboardViewController: InputEngineDelegate {

    func engineDidUpdateComposing(_ text: String) {
        DispatchQueue.main.async {
            self.showingSuggestions = false
            self.candidateBar.setComposing(text)
            self.syncPageWithEngine()
        }
    }

    func engineDidUpdateCandidates(_ candidates: [String]) {
        DispatchQueue.main.async {
            if self.showingSuggestions { return }
            self.candidateBar.setCandidates(candidates, suggestions: false)
            if candidates.isEmpty && self.engine.composing.isEmpty {
                self.refreshIdleBar()
            }
            self.syncPageWithEngine()
        }
    }

    func engineDidCommit(_ text: String) {
        DispatchQueue.main.async {
            self.textDocumentProxy.insertText(text)
        }
    }

    func engineDidCommitPair(_ left: String, _ right: String) {
        DispatchQueue.main.async {
            self.textDocumentProxy.insertText(left + right)
            self.textDocumentProxy.adjustTextPosition(byCharacterOffset: -right.count)
        }
    }

    func engineDidClearComposing() {
        DispatchQueue.main.async {
            self.candidateBar.setComposing("")
            if !self.showingSuggestions { self.refreshIdleBar() }
            self.syncPageWithEngine()
        }
    }

    func engineDidShowToast(_ text: String) {
        DispatchQueue.main.async { self.showToast(text, duration: 1.2) }
    }

    func engineDidShowCodeHint(_ text: String, duration: Double) {
        DispatchQueue.main.async { self.showToast(text, duration: duration) }
    }

    func engineDidDeleteBack() {
        DispatchQueue.main.async {
            self.textDocumentProxy.deleteBackward()
        }
    }

    func engineDidSuggest(_ suggestions: [String]) {
        DispatchQueue.main.async {
            self.showingSuggestions = true
            self.engine.setCandidates(suggestions)
            self.candidateBar.setComposing("")
            self.candidateBar.setCandidates(suggestions, suggestions: true)
        }
    }

    func engineDidPasteText(_ text: String) {
        DispatchQueue.main.async {
            self.textDocumentProxy.insertText(text)
        }
    }

    private func showToast(_ text: String, duration: Double) {
        toastWorkItem?.cancel()
        toastLabel.text = "  \(text)  "
        toastLabel.isHidden = false
        toastLabel.alpha = 1
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.25, animations: { self?.toastLabel.alpha = 0 }) { _ in
                self?.toastLabel.isHidden = true
            }
        }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
