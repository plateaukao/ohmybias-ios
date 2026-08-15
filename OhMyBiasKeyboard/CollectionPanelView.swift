import UIKit

/// 分類面板 — sweetlime 符號/Emoji/顏文字鍵盤：左欄分類、右欄格狀內容、底列返回/退格。
/// 顏色由 cskin 的 panel 色鍵控制；未設定時跟隨系統深淺色。
final class CollectionPanelView: UIView {

    var onInsert: ((String) -> Void)?
    var onBack: (() -> Void)?
    var onBackspace: (() -> Void)?

    private let sections: [(String, [String])]
    private let itemFontSize: CGFloat
    private var currentSection = 0
    private var categoryButtons: [UIButton] = []
    private var bottomButtons: [UIButton] = []
    private let categoryScroll = UIScrollView()
    private let categoryStack = UIStackView()
    private var collectionView: UICollectionView!

    init(sections: [(String, [String])], itemFontSize: CGFloat) {
        self.sections = sections
        self.itemFontSize = itemFontSize
        super.init(frame: .zero)
        backgroundColor = KeyboardTheme.panelRightBackground

        // 左欄分類
        categoryScroll.showsVerticalScrollIndicator = false
        categoryScroll.backgroundColor = KeyboardTheme.panelLeftBackground
        categoryScroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(categoryScroll)
        categoryStack.axis = .vertical
        categoryStack.spacing = 2
        categoryStack.translatesAutoresizingMaskIntoConstraints = false
        categoryScroll.addSubview(categoryStack)
        for (i, (name, _)) in sections.enumerated() {
            let b = UIButton(type: .custom)
            b.setTitle(name, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 15)
            b.tag = i
            b.layer.cornerRadius = 6
            b.heightAnchor.constraint(equalToConstant: 34).isActive = true
            b.addTarget(self, action: #selector(didTapCategory(_:)), for: .touchUpInside)
            categoryStack.addArrangedSubview(b)
            categoryButtons.append(b)
        }

        // 右欄內容格
        let layout = UICollectionViewFlowLayout()
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        layout.sectionInset = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = KeyboardTheme.panelRightBackground
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PanelCell.self, forCellWithReuseIdentifier: "cell")
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.contentInset.bottom = 48  // 避免內容被浮動退格鍵遮住
        addSubview(collectionView)

        // 底列：返回＋退格
        let backButton = bottomButton("返回", #selector(didTapBack))
        let backspaceButton = bottomButton("⌫", #selector(didTapBackspace))

        NSLayoutConstraint.activate([
            categoryScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            categoryScroll.topAnchor.constraint(equalTo: topAnchor),
            categoryScroll.widthAnchor.constraint(equalToConstant: 64),
            categoryScroll.bottomAnchor.constraint(equalTo: backButton.topAnchor),
            categoryStack.leadingAnchor.constraint(equalTo: categoryScroll.contentLayoutGuide.leadingAnchor, constant: 4),
            categoryStack.trailingAnchor.constraint(equalTo: categoryScroll.contentLayoutGuide.trailingAnchor, constant: -4),
            categoryStack.topAnchor.constraint(equalTo: categoryScroll.contentLayoutGuide.topAnchor, constant: 4),
            categoryStack.bottomAnchor.constraint(equalTo: categoryScroll.contentLayoutGuide.bottomAnchor, constant: -4),
            categoryStack.widthAnchor.constraint(equalTo: categoryScroll.frameLayoutGuide.widthAnchor, constant: -8),
            collectionView.leadingAnchor.constraint(equalTo: categoryScroll.trailingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            backButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            backButton.widthAnchor.constraint(equalToConstant: 56),
            backButton.heightAnchor.constraint(equalToConstant: 40),
            backspaceButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            backspaceButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            backspaceButton.widthAnchor.constraint(equalToConstant: 56),
            backspaceButton.heightAnchor.constraint(equalToConstant: 40),
        ])
        highlightCategory()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func bottomButton(_ title: String, _ selector: Selector) -> UIButton {
        let b = UIButton(type: .custom)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: KeyboardTheme.systemFontSize + 2)
        b.setTitleColor(KeyboardTheme.textSystem, for: .normal)
        b.backgroundColor = KeyboardTheme.keySystem
        b.layer.cornerRadius = KeyboardTheme.cornerRadius
        b.layer.borderWidth = KeyboardTheme.borderWidth
        b.layer.borderColor = KeyboardTheme.systemBorder.resolvedColor(with: traitCollection).cgColor
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: selector, for: .touchUpInside)
        addSubview(b)
        bottomButtons.append(b)
        return b
    }

    private func highlightCategory() {
        for (i, b) in categoryButtons.enumerated() {
            let selected = i == currentSection
            b.backgroundColor = selected ? KeyboardTheme.panelCategoryHighlight : .clear
            b.setTitleColor(selected ? KeyboardTheme.panelCategorySelectedText : KeyboardTheme.panelText, for: .normal)
        }
    }

    @objc private func didTapCategory(_ sender: UIButton) {
        currentSection = sender.tag
        highlightCategory()
        collectionView.reloadData()
        collectionView.setContentOffset(.zero, animated: false)
    }

    @objc private func didTapBack() { onBack?() }
    @objc private func didTapBackspace() { onBackspace?() }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        for button in bottomButtons {
            button.layer.borderColor = KeyboardTheme.systemBorder.resolvedColor(with: traitCollection).cgColor
        }
    }
}

extension CollectionPanelView: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[currentSection].1.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! PanelCell
        cell.configure(sections[currentSection].1[indexPath.item], fontSize: itemFontSize)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onInsert?(sections[currentSection].1[indexPath.item])
    }
}

/// 面板格子 — 自動尺寸的圓角標籤
final class PanelCell: UICollectionViewCell {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 6
        label.textAlignment = .center
        label.textColor = KeyboardTheme.panelText
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            contentView.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ text: String, fontSize: CGFloat) {
        label.text = text
        label.font = .systemFont(ofSize: fontSize)
    }

    override var isHighlighted: Bool {
        didSet { contentView.backgroundColor = isHighlighted ? KeyboardTheme.keyNormalHighlight : .clear }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if isHighlighted {
            contentView.backgroundColor = KeyboardTheme.keyNormalHighlight
        }
    }
}
