import UIKit

/// 候選字列：左側 composing 碼、右側水平捲動候選字／聯想詞。
/// 空閒時顯示目前輸入法模式＋sweetlime 工具列（組字/候選出現時自動隱藏）。
final class CandidateBar: UIView {

    static let barHeight: CGFloat = 46

    var onSelect: ((Int) -> Void)?
    /// 工具列按鈕動作（路由至 KeyboardViewController.handleKey）
    var onToolbarKey: ((KeyAction) -> Void)?
    /// 點組字碼標籤 — 把打的字母原樣上屏（要英文單字不要候選時）
    var onCommitComposing: (() -> Void)?
    /// 點聯想詞列左側 ✕ — 關閉聯想、回到空閒工具列
    var onDismissSuggestions: (() -> Void)?

    private let composingLabel = UILabel()
    private let dismissButton = UIButton(type: .system)
    private var dismissWidth: NSLayoutConstraint!
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let toolbarStack = UIStackView()
    private var languageButton: UIButton?

    /// 工具列項目：由 cskin 的 toolbarButtons 按鈕 ID 對應而來
    private struct ToolbarItem {
        let icon: String?    // SF Symbol 名稱
        let text: String?    // 無合適圖示時用文字
        let label: String    // accessibility label（VoiceOver／UI 測試）
        let action: KeyAction
        var isLanguage = false
    }

    /// Hamster 按鈕 ID → 本鍵盤可實作的項目；nil = 不可實作 → 空白佔位。
    /// （4 簡繁、6 剪貼本、10-12/14-15 編輯、18-25/31 Hamster 專屬 → 空）
    private static func item(forButtonID id: Int) -> ToolbarItem? {
        switch id {
        case 1:  return ToolbarItem(icon: "gearshape", text: nil, label: "設定", action: .openSettings)
        case 2:  return ToolbarItem(icon: "chevron.down", text: nil, label: "收折鍵盤", action: .dismissKeyboard)
        case 3:  return ToolbarItem(icon: nil, text: "米", label: "中英切換", action: .toggleLanguage, isLanguage: true)
        case 5:  return ToolbarItem(icon: "heart.fill", text: nil, label: "常用語", action: .toggleToolbarPage(.phrases))
        case 7:  return ToolbarItem(icon: "curlybraces", text: nil, label: "符號面板", action: .toggleToolbarPage(.symbolPanel))
        case 8:  return ToolbarItem(icon: "face.smiling", text: nil, label: "Emoji", action: .toggleToolbarPage(.emoji))
        case 9:
            let page: KeyboardView.Page = SkinSettings.shared.keyboardLayout == "row" ? .numbers : .numeric9
            return ToolbarItem(icon: "textformat.123", text: nil, label: "數字鍵盤", action: .toggleToolbarPage(page))
        // 全選在 iOS 鍵盤 extension 無 API 不可實作 — 依使用者決定，此位置固定放 ♥ 常用語
        case 10: return ToolbarItem(icon: "heart.fill", text: nil, label: "常用語", action: .toggleToolbarPage(.phrases))
        case 13: return ToolbarItem(icon: "doc.on.clipboard", text: nil, label: "貼上", action: .pasteClipboard)
        case 16: return ToolbarItem(icon: "arrow.left", text: nil, label: "游標左移", action: .cursorLeft)
        case 17: return ToolbarItem(icon: "arrow.right", text: nil, label: "游標右移", action: .cursorRight)
        case 26: return ToolbarItem(icon: nil, text: "顏", label: "顏文字", action: .toggleToolbarPage(.kaomojis))
        case 27: return ToolbarItem(icon: nil, text: "ㄅ", label: "注音查碼", action: .enterZhuyin)
        case 29: return ToolbarItem(icon: "textformat.123", text: nil, label: "九宮格數字", action: .toggleToolbarPage(.numeric9))
        case 30: return ToolbarItem(icon: "curlybraces", text: nil, label: "符號面板", action: .toggleToolbarPage(.symbolPanel))
        default: return nil
        }
    }

    /// 語言鍵顯示目前輸入法：嘸蝦米 →「米」、英文 →「英」
    func setEnglishMode(_ isEnglish: Bool) {
        // .system 按鈕會對 setTitle 做隱式淡入淡出 — 切換要即時，關掉
        UIView.performWithoutAnimation {
            languageButton?.setTitle(isEnglish ? "英" : "米", for: .normal)
            languageButton?.layoutIfNeeded()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // 玻璃模式：工具列背景交給系統玻璃，只保留按鈕與文字內容
        backgroundColor = KeyboardTheme.glassHost ? .clear : KeyboardTheme.toolbarBackground

        composingLabel.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        composingLabel.textColor = KeyboardTheme.textSub
        composingLabel.setContentHuggingPriority(.required, for: .horizontal)
        composingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        composingLabel.translatesAutoresizingMaskIntoConstraints = false
        // 組字碼本身可點 — 有候選但要英文單字時，點了原樣上屏
        composingLabel.isUserInteractionEnabled = true
        composingLabel.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(composingTapped)))
        addSubview(composingLabel)

        // 聯想詞列左側 ✕：不想要聯想時一鍵關閉（平時寬 0 收起）
        let xConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        dismissButton.setImage(UIImage(systemName: "xmark", withConfiguration: xConfig), for: .normal)
        dismissButton.tintColor = KeyboardTheme.textSub
        dismissButton.accessibilityLabel = "關閉聯想"
        dismissButton.isHidden = true
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.addAction(UIAction { [weak self] _ in self?.onDismissSuggestions?() },
                                for: .touchUpInside)
        addSubview(dismissButton)

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stack.axis = .horizontal
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        toolbarStack.axis = .horizontal
        toolbarStack.distribution = .fillEqually
        toolbarStack.spacing = 4
        toolbarStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbarStack)
        // 照 cskin toolbarButtons 序列建構；做不到的按鈕 ID（含 0 佔位符）留空格
        for id in SkinSettings.shared.toolbarButtons {
            guard let item = Self.item(forButtonID: id) else {
                toolbarStack.addArrangedSubview(UIView())
                continue
            }
            let b = UIButton(type: .system)
            if let icon = item.icon {
                let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
                b.setImage(UIImage(systemName: icon, withConfiguration: config), for: .normal)
                b.tintColor = KeyboardTheme.toolbarColor
            } else if let text = item.text {
                b.setTitle(text, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 19)
                b.setTitleColor(KeyboardTheme.toolbarColor, for: .normal)
            }
            b.accessibilityLabel = item.label
            let action = item.action
            b.addAction(UIAction { [weak self] _ in self?.onToolbarKey?(action) }, for: .touchUpInside)
            toolbarStack.addArrangedSubview(b)
            if item.isLanguage { languageButton = b }
        }

        dismissWidth = dismissButton.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            composingLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            composingLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            toolbarStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            toolbarStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            toolbarStack.topAnchor.constraint(equalTo: topAnchor),
            toolbarStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            dismissButton.leadingAnchor.constraint(equalTo: composingLabel.trailingAnchor),
            dismissButton.topAnchor.constraint(equalTo: topAnchor),
            dismissButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            dismissWidth,
            scrollView.leadingAnchor.constraint(equalTo: dismissButton.trailingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -2),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
        updateToolbarVisibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 上次顯示內容 — 相同就完全不動（每個按鍵/每次切輸入框都會重設候選列）
    private var lastCandidates: [String] = []
    private var lastSuggestions = false
    /// stack 目前作用中的按鈕數（多餘的隱藏備用，取代每鍵擊 removeFromSuperview + 新建）
    private var activeButtons = 0

    /// 空閒（無組字、無候選）才顯示工具列；候選捲動區與其互斥
    private func updateToolbarVisibility() {
        let idle = (composingLabel.text ?? "").isEmpty && activeButtons == 0
        toolbarStack.isHidden = !idle
        scrollView.isHidden = idle
    }

    func setComposing(_ text: String) {
        if (composingLabel.text ?? "") == text { return }  // 未變就不重排
        composingLabel.text = text
        updateToolbarVisibility()
    }

    /// 從 stack 取第 index 顆按鈕重用，不夠才建（取代每鍵擊 removeFromSuperview + 新建）
    private func obtainButton(at index: Int) -> UIButton {
        while stack.arrangedSubviews.count <= index {
            let b = UIButton(type: .system)
            b.titleLabel?.font = .systemFont(ofSize: 20)
            b.contentEdgeInsets = UIEdgeInsets(top: 4, left: 9, bottom: 4, right: 9)
            b.layer.cornerRadius = 6
            b.addTarget(self, action: #selector(didTap(_:)), for: .touchUpInside)
            stack.addArrangedSubview(b)
        }
        let b = stack.arrangedSubviews[index] as! UIButton
        b.isHidden = false
        return b
    }

    func setCandidates(_ candidates: [String], suggestions: Bool) {
        // 內容未變就完全不動 — refreshIdleBar 常以空列表重複呼叫
        if suggestions == lastSuggestions && candidates == lastCandidates { return }
        lastCandidates = candidates
        lastSuggestions = suggestions
        scrollView.setContentOffset(.zero, animated: false)
        defer { updateToolbarVisibility() }

        // 候選 1–2 個時不顯示數字前綴（與 macOS 版一致的精簡顯示）
        let showIndex = candidates.count > 2 && !suggestions
        // .system 按鈕會對 setTitle 做隱式淡入淡出（約 0.25s）— 候選要即時出現，關掉
        UIView.performWithoutAnimation {
            // 聯想詞列才顯示左側 ✕（一般候選不能關 — 是組字狀態的一部分）
            let showDismiss = suggestions && !candidates.isEmpty
            dismissButton.isHidden = !showDismiss
            dismissWidth.constant = showDismiss ? 30 : 0
            for (i, c) in candidates.enumerated() {
                let b = obtainButton(at: i)
                let title = showIndex && i < 9 ? "\(i + 1) \(c)" : c
                b.setTitle(title, for: .normal)
                b.setTitleColor(suggestions ? .systemBlue : KeyboardTheme.candidateText, for: .normal)
                if i == 0 && !suggestions && candidates.count > 2 {
                    b.setTitleColor(KeyboardTheme.candidateSelectedText, for: .normal)
                    b.backgroundColor = KeyboardTheme.candidateSelectedBackground
                    b.layer.borderWidth = KeyboardTheme.borderWidth(for: traitCollection)
                    b.layer.borderColor = KeyboardTheme.border.resolvedColor(with: traitCollection).cgColor
                } else {
                    b.backgroundColor = nil
                    b.layer.borderWidth = 0
                }
                b.tag = i
            }
            activeButtons = candidates.count
            for j in candidates.count..<stack.arrangedSubviews.count {
                stack.arrangedSubviews[j].isHidden = true
            }
            stack.layoutIfNeeded()
        }
    }

    @objc private func didTap(_ sender: UIButton) {
        onSelect?(sender.tag)
    }

    @objc private func composingTapped() {
        onCommitComposing?()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // CGColor 不會自動跟隨深淺色，且 setCandidates 內容未變時短路不重設 —
        // 這裡重解選中候選（第 0 顆）的邊框
        if activeButtons > 0, let b = stack.arrangedSubviews.first as? UIButton,
           b.layer.borderWidth > 0 {
            b.layer.borderWidth = KeyboardTheme.borderWidth(for: traitCollection)
            b.layer.borderColor = KeyboardTheme.border.resolvedColor(with: traitCollection).cgColor
        }
    }
}
