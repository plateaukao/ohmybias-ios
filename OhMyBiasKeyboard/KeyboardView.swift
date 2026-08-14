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
}

/// 純程式碼鍵盤面板：字母頁／數字頁／符號頁／注音查碼頁。
final class KeyboardView: UIView {

    enum Page { case letters, numbers, symbols, zhuyin }

    var onKey: ((KeyAction) -> Void)?
    /// 地球鍵需綁 handleInputModeList — 由 controller 提供
    var onGlobeSetup: ((UIButton) -> Void)?

    var currentPage: Page = .letters
    var isEnglishMode = false
    var isShifted = false
    var needsInputModeSwitchKey = true

    private let rowsStack = UIStackView()
    private var backspaceTimer: Timer?

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
        let rows: [[KeySpec]]
        switch currentPage {
        case .letters: rows = letterRows()
        case .numbers: rows = numberRows()
        case .symbols: rows = symbolRows()
        case .zhuyin:  rows = zhuyinRows()
        }
        for row in rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillProportionally
            rowStack.spacing = 5
            for spec in row {
                let b = makeKey(spec)
                rowStack.addArrangedSubview(b)
                if spec.widthMultiplier != 1, let first = rowStack.arrangedSubviews.first(where: { ($0 as? KeyButton)?.spec.widthMultiplier == 1 }) {
                    b.widthAnchor.constraint(equalTo: first.widthAnchor, multiplier: spec.widthMultiplier).isActive = true
                }
            }
            // 等寬鍵之間互相對齊
            let unitKeys = rowStack.arrangedSubviews.compactMap { $0 as? KeyButton }.filter { $0.spec.widthMultiplier == 1 }
            for k in unitKeys.dropFirst() {
                k.widthAnchor.constraint(equalTo: unitKeys[0].widthAnchor).isActive = true
            }
            rowsStack.addArrangedSubview(rowStack)
        }
    }

    struct KeySpec {
        let label: String
        let action: KeyAction
        var widthMultiplier: CGFloat = 1
        var isSpecial = false      // 灰色功能鍵底色
        var isGlobe = false
    }

    private func letterRows() -> [[KeySpec]] {
        let r1 = "qwertyuiop".map { String($0) }
        let r2 = "asdfghjkl".map { String($0) }
        let r3 = "zxcvbnm".map { String($0) }
        func key(_ s: String) -> KeySpec {
            KeySpec(label: isEnglishMode && isShifted ? s.uppercased() : s, action: .letter(s))
        }
        var row3: [KeySpec] = []
        if isEnglishMode {
            row3.append(KeySpec(label: isShifted ? "⬆" : "⇧", action: .shift, widthMultiplier: 1.4, isSpecial: true))
        } else {
            row3.append(KeySpec(label: ",", action: .letter(","), widthMultiplier: 1.4))
        }
        row3 += r3.map(key)
        row3.append(KeySpec(label: "⌫", action: .backspace, widthMultiplier: 1.4, isSpecial: true))

        var row4: [KeySpec] = [
            KeySpec(label: "123", action: .page(.numbers), widthMultiplier: 1.3, isSpecial: true),
        ]
        if needsInputModeSwitchKey {
            row4.append(KeySpec(label: "🌐", action: .space, widthMultiplier: 1.1, isSpecial: true, isGlobe: true))
        }
        row4.append(KeySpec(label: isEnglishMode ? "英" : "嘸", action: .toggleLanguage, widthMultiplier: 1.1, isSpecial: true))
        row4.append(KeySpec(label: "空白", action: .space, widthMultiplier: 4.2))
        row4.append(KeySpec(label: isEnglishMode ? "." : "。", action: .letter("."), widthMultiplier: 1.1))
        row4.append(KeySpec(label: "⏎", action: .newline, widthMultiplier: 1.6, isSpecial: true))

        return [r1.map(key), r2.map(key), row3, row4]
    }

    private func numberRows() -> [[KeySpec]] {
        let r1 = "1234567890".map { String($0) }
        let r2 = ["-", "/", "：", "；", "（", "）", "＄", "＠", "「", "」"]
        let r3 = ["。", "，", "、", "？", "！", "．", "…", "～"]
        var row3: [KeySpec] = [KeySpec(label: "#+=", action: .page(.symbols), widthMultiplier: 1.4, isSpecial: true)]
        row3 += r3.map { KeySpec(label: $0, action: .symbol($0)) }
        row3.append(KeySpec(label: "⌫", action: .backspace, widthMultiplier: 1.4, isSpecial: true))
        let row4: [KeySpec] = [
            KeySpec(label: "嘸", action: .page(.letters), widthMultiplier: 1.5, isSpecial: true),
            KeySpec(label: "空白", action: .space, widthMultiplier: 5.5),
            KeySpec(label: "⏎", action: .newline, widthMultiplier: 1.8, isSpecial: true),
        ]
        return [r1.map { KeySpec(label: $0, action: .letter($0)) }, r2.map { KeySpec(label: $0, action: .symbol($0)) }, row3, row4]
    }

    private func symbolRows() -> [[KeySpec]] {
        let r1 = ["［", "］", "｛", "｝", "＃", "％", "＾", "＊", "＋", "＝"]
        let r2 = ["＿", "＼", "｜", "～", "＜", "＞", "《", "》", "€", "＆"]
        let r3 = ["『", "』", "【", "】", "〈", "〉", "・", "§"]
        var row3: [KeySpec] = [KeySpec(label: "123", action: .page(.numbers), widthMultiplier: 1.4, isSpecial: true)]
        row3 += r3.map { KeySpec(label: $0, action: .symbol($0)) }
        row3.append(KeySpec(label: "⌫", action: .backspace, widthMultiplier: 1.4, isSpecial: true))
        let row4: [KeySpec] = [
            KeySpec(label: "嘸", action: .page(.letters), widthMultiplier: 1.5, isSpecial: true),
            KeySpec(label: "空白", action: .space, widthMultiplier: 5.5),
            KeySpec(label: "⏎", action: .newline, widthMultiplier: 1.8, isSpecial: true),
        ]
        return [r1.map { KeySpec(label: $0, action: .symbol($0)) }, r2.map { KeySpec(label: $0, action: .symbol($0)) }, row3, row4]
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
            b.addTarget(self, action: #selector(keyDown(_:)), for: .touchDown)
            b.addTarget(self, action: #selector(keyUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        }
        return b
    }

    @objc private func keyDown(_ sender: KeyButton) {
        if case .backspace = sender.spec.action {
            onKey?(.backspace)
            backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                self?.backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                    self?.onKey?(.backspace)
                }
            }
        }
    }

    @objc private func keyUp(_ sender: KeyButton) {
        if case .backspace = sender.spec.action {
            backspaceTimer?.invalidate(); backspaceTimer = nil
            return
        }
        onKey?(sender.spec.action)
    }
}

/// 圓角按鍵
final class KeyButton: UIButton {
    let spec: KeyboardView.KeySpec

    init(spec: KeyboardView.KeySpec) {
        self.spec = spec
        super.init(frame: .zero)
        setTitle(spec.label, for: .normal)
        titleLabel?.font = .systemFont(ofSize: spec.label.count > 1 ? 16 : 22)
        setTitleColor(.label, for: .normal)
        backgroundColor = spec.isSpecial
            ? UIColor.secondarySystemFill
            : UIColor.tertiarySystemBackground
        layer.cornerRadius = 6
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.5 : 1 }
    }
}
