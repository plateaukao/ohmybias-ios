import UIKit

/// 候選字列：左側 composing 碼、右側水平捲動候選字／聯想詞。
/// 空閒時顯示目前輸入法模式。
final class CandidateBar: UIView {

    static let barHeight: CGFloat = 46

    var onSelect: ((Int) -> Void)?

    private let composingLabel = UILabel()
    private let idleLabel = UILabel()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        composingLabel.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        composingLabel.textColor = .secondaryLabel
        composingLabel.setContentHuggingPriority(.required, for: .horizontal)
        composingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        composingLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(composingLabel)

        idleLabel.font = .systemFont(ofSize: 14)
        idleLabel.textColor = .tertiaryLabel
        idleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(idleLabel)

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stack.axis = .horizontal
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            composingLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            composingLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            idleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            idleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            scrollView.leadingAnchor.constraint(equalTo: composingLabel.trailingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -2),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setComposing(_ text: String) {
        composingLabel.text = text
        if !text.isEmpty { idleLabel.text = "" }
    }

    func setIdleLabel(_ text: String) {
        idleLabel.text = text
    }

    func setCandidates(_ candidates: [String], suggestions: Bool) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        scrollView.setContentOffset(.zero, animated: false)
        if !candidates.isEmpty { idleLabel.text = "" }
        // 候選 1–2 個時不顯示數字前綴（與 macOS 版一致的精簡顯示）
        let showIndex = candidates.count > 2 && !suggestions
        for (i, c) in candidates.enumerated() {
            let b = UIButton(type: .system)
            let title = showIndex && i < 9 ? "\(i + 1) \(c)" : c
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 20)
            b.setTitleColor(suggestions ? .systemBlue : .label, for: .normal)
            b.contentEdgeInsets = UIEdgeInsets(top: 4, left: 9, bottom: 4, right: 9)
            b.layer.cornerRadius = 6
            if i == 0 && !suggestions && candidates.count > 2 {
                b.backgroundColor = UIColor.systemFill
            }
            b.tag = i
            b.addTarget(self, action: #selector(didTap(_:)), for: .touchUpInside)
            stack.addArrangedSubview(b)
        }
    }

    @objc private func didTap(_ sender: UIButton) {
        onSelect?(sender.tag)
    }
}
