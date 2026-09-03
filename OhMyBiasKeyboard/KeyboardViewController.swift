import UIKit
import SwiftUI

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
    /// 目前欄位是密碼／純 ASCII 類 — 暫時切英文直通、換欄位還原使用者的中英狀態。
    /// 密碼不該經過組字；容器 app 常用語設定的「組字碼」欄（asciiCapable）也靠這個讓使用者
    /// 直接打碼不被組成中文。
    private var forcedEnglishForField = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        SkinSettings.shared.reload()  // 讀取匯入的 cskin 設定（工具列/配色/字級/版面）
        CoreTextGlyphCache.install()  // 攔截 CoreText 的 emoji 字形快取，面板收掉時才能真的把記憶體要回來
        MemoryBudget.extraRelief = { CoreTextGlyphCache.drain() }  // 引擎層釋放快取時一併清字形
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
        // 容器 app 匯入過新字表／改過常用語（含組字碼）— extension 行程可能還活著，比對檔案時間重載
        engine.cinTable.reloadIfBinChanged()
        engine.cinTable.reloadShortcutsIfNeeded()
        syncFieldEnglishMode(reapplyPrefs: true)
        // 只有鍵面實際會變才重建按鍵（syncSessionState 內比對短路）
        keyboardView.syncSessionState(
            needsSwitchKey: needsInputModeSwitchKey,
            returnLabel: Self.returnLabel(for: textDocumentProxy.returnKeyType)
        )
    }

    /// 換輸入欄位（同一 host app 內焦點移動不會重跑 viewWillAppear）
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        syncFieldEnglishMode()
    }

    /// 密碼類（secure）與 asciiCapable 欄位暫時英文直通（不寫 lastEnglishMode — 離開欄位就還原）。
    /// `reapplyPrefs`：鍵盤每次出現時連偏好裡的中英狀態一起重套 — 容器 app 匯入 liu.cin 會把它
    /// 歸零成中文，而 extension 行程可能還活著、viewDidLoad 讀的是舊值。
    /// 逐鍵的 textDidChange 不重套：在密碼欄手動切回中文（不存偏好）不能被下一鍵又切回英文
    private func syncFieldEnglishMode(reapplyPrefs: Bool = false) {
        let proxy = textDocumentProxy
        let forced = (proxy.isSecureTextEntry ?? false) || proxy.keyboardType == .asciiCapable
        let want = forced ? true : OhMyBiasPrefs.lastEnglishMode
        guard forced != forcedEnglishForField || (reapplyPrefs && want != engine.isEnglishMode) else { return }
        forcedEnglishForField = forced
        engine.setEnglishMode(want)
        keyboardView.isEnglishMode = engine.isEnglishMode
        refreshIdleBar()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 收鍵盤時把未寫入的字頻紀錄落盤 — extension 被殺也不掉學習資料
        engine.freqTracker.flushAll()
        // 面板留著沒人看，但 cell／圖層／SwiftUI 會一直佔記憶體 — 收鍵盤即拆
        if let host = settingsPanelHost { dismissSettingsPanel(host) }
        keyboardView.releasePanels()
        // 記憶體偏高時釋放可選快取（反查表、繁簡表、注音表）— 不清會活到行程被殺為止
        MemoryBudget.trimIfNeeded(cinTable: engine.cinTable)
    }

    /// 系統送記憶體警告（約上限的七成）= 被 jetsam 殺掉前的最後機會，能放的全放。
    /// 先放快取（反查表、注音表、emoji 字形）再量一次 — 通常光這樣就退回安全區；
    /// 使用者正在看的面板是最後才拆的東西，否則「面板一開就被收掉」本身就是 bug。
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        MemoryBudget.releaseAll(cinTable: engine.cinTable)
        guard MemoryBudget.isCritical else { return }
        if let host = settingsPanelHost { dismissSettingsPanel(host) }
        keyboardView.releasePanels()
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

        keyboardView.yieldTopMargin = { [weak self] in self?.candidateBar.hasScrollableCandidates ?? false }
        candidateBar.onSelect = { [weak self] idx in self?.didSelectCandidate(at: idx) }
        candidateBar.onToolbarKey = { [weak self] action in self?.handleKey(action) }
        candidateBar.onDismissSuggestions = { [weak self] in self?.clearSuggestions() }
        candidateBar.onCommitComposing = { [weak self] in
            guard let self else { return }
            if OhMyBiasPrefs.hapticFeedback {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            self.engine.commitComposingRaw()
        }
        keyboardView.onKey = { [weak self] action in self?.handleKey(action) }
        keyboardView.onPanelMemoryRelief = { [weak self] in
            guard let self else { return }
            MemoryBudget.releaseAll(cinTable: self.engine.cinTable)
        }
        keyboardView.onPanelUnavailable = { [weak self] in
            // 帶上實測數字 — 使用者回報時就能看出這台機器的真實上限
            self?.showToast("記憶體不足，暫時無法開啟面板（\(MemoryBudget.summary)）", duration: 2)
        }
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
        // 設定面板開著時點了其他工具列按鈕 — 先收面板，避免動作發生在面板底下
        if let host = settingsPanelHost {
            if case .openSettings = action {} else { dismissSettingsPanel(host) }
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
            // 符號頁直接送出（不經引擎組字）；成對標點仍補右半並把游標放中間
            engine.handleEscape()
            if let right = engine.pairedRight(s) {
                commitPair(s, right)
            } else {
                textDocumentProxy.insertText(s)
            }
        case .toggleLanguage:
            engine.toggleEnglishMode()
            keyboardView.isEnglishMode = engine.isEnglishMode
            keyboardView.showPage(.letters)  // 從工具列切換時回到字母頁
            // 密碼／ASCII 欄位的暫時英文是欄位性質，不是使用者偏好 — 不記
            if !forcedEnglishForField { OhMyBiasPrefs.lastEnglishMode = engine.isEnglishMode }
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
            toggleSettingsPanel()
        }
    }

    // MARK: - ⚙ 設定面板（,, 指令速查）

    private var settingsPanelHost: UIViewController?

    /// 點齒輪展開/收起 — SwiftUI runtime（~10MB）在首次展開時才載入
    private func toggleSettingsPanel() {
        if let host = settingsPanelHost { dismissSettingsPanel(host); return }
        guard MemoryBudget.makeRoom(for: MemoryBudget.settingsPanel, cinTable: engine.cinTable) else {
            showToast("記憶體不足，暫時無法開啟面板（\(MemoryBudget.summary)）", duration: 2)
            return
        }
        let panel = SettingsPanelView(
            onCommand: { [weak self] cmd in
                guard let self else { return }
                if let host = self.settingsPanelHost { self.dismissSettingsPanel(host) }
                self.engine.runCommaCommand(cmd)
            },
            onDismiss: { [weak self] in
                guard let self, let host = self.settingsPanelHost else { return }
                self.dismissSettingsPanel(host)
            })
        let host = UIHostingController(rootView: panel)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        // 不透明底色 + 關掉鍵面互動：SwiftUI hosting view 在無內容處 hitTest 會回 nil，
        // 觸控就會穿透到 KeyboardView.hitTest 的「最近按鍵」後援而誤打字
        host.view.backgroundColor = KeyboardTheme.panelRightBackground
        keyboardView.isUserInteractionEnabled = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: keyboardView.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: keyboardView.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: keyboardView.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: keyboardView.bottomAnchor),
        ])
        host.didMove(toParent: self)
        settingsPanelHost = host
    }

    private func dismissSettingsPanel(_ host: UIViewController) {
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        settingsPanelHost = nil
        keyboardView.isUserInteractionEnabled = true
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
        // 查碼模式優先於英文模式 — 英打切到注音/拼音查碼時，空白是一聲/查碼，
        // 不是直通空格（android issue #6 同款）
        if engine.isPinyinMode { engine.handlePinyinSpace(); return }
        if engine.isZhuyinMode { engine.handleZhuyinSpace(); return }
        if engine.isEnglishMode { textDocumentProxy.insertText(" "); return }
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
        // 同 handleSpaceKey：查碼模式優先於英文模式（退格要清注音槽，不是刪編輯框）
        if engine.isPinyinMode { engine.handlePinyinBackspace(); return }
        if engine.isZhuyinMode { engine.handleBackspace(); return }
        if engine.isEnglishMode { textDocumentProxy.deleteBackward(); return }
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
        DispatchQueue.main.async { self.commitPair(left, right) }
    }

    /// 送出成對標點並把游標移回中間（引擎送字與符號鍵共用；已在主執行緒）
    private func commitPair(_ left: String, _ right: String) {
        textDocumentProxy.insertText(left + right)
        textDocumentProxy.adjustTextPosition(byCharacterOffset: -right.count)
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
        view.bringSubviewToFront(toastLabel)  // 設定面板可能疊在鍵面上 — toast 要蓋過它
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
