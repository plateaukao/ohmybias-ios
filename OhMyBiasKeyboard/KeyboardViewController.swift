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
        engine = InputEngine()
        engine.delegate = self
        engine.loadTable()
        engine.scheduleBackgroundTasks()
        setUpViews()
        refreshIdleBar()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        keyboardView.needsInputModeSwitchKey = needsInputModeSwitchKey
        keyboardView.reloadKeys()
    }

    override func updateViewConstraints() {
        super.updateViewConstraints()
        let isLandscape = view.bounds.width > 500
        let height: CGFloat = (isLandscape ? 180 : 224) + CandidateBar.barHeight
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
            keyboardView.reloadKeys()
        case .page(let page):
            keyboardView.currentPage = page
            keyboardView.reloadKeys()
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
        }
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
        candidateBar.setIdleLabel(engine.currentModeLabel)
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
