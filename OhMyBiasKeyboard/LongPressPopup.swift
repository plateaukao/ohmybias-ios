import UIKit

/// 長按彈出選單 — sweetlime 氣泡樣式：外殼淺底圓角、選中項反白。
/// 水平滑動選擇、放開送出。
final class LongPressPopup: UIView {

    static let itemHeight: CGFloat = 44

    private let itemLabels: [UILabel]
    private let itemWidth: CGFloat
    private(set) var selectedIndex: Int

    init(options: [LongPressData.Option], defaultIndex: Int) {
        // 中文選項（時間/日期…）較寬
        let wide = options.contains { $0.label.count > 1 }
        itemWidth = wide ? 52 : 40
        selectedIndex = defaultIndex
        itemLabels = options.map { opt in
            let l = UILabel()
            l.text = opt.label
            l.font = .systemFont(ofSize: opt.label.count > 1 ? 15 : 22)
            l.textAlignment = .center
            l.layer.cornerRadius = 6
            l.layer.masksToBounds = true
            return l
        }
        super.init(frame: CGRect(x: 0, y: 0,
                                 width: itemWidth * CGFloat(options.count) + 8,
                                 height: Self.itemHeight))
        backgroundColor = KeyboardTheme.bubbleShellBackground
        layer.cornerRadius = KeyboardTheme.cornerRadius
        layer.borderWidth = KeyboardTheme.borderWidth(for: traitCollection)
        layer.borderColor = KeyboardTheme.border.resolvedColor(with: traitCollection).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)
        for (i, l) in itemLabels.enumerated() {
            l.frame = CGRect(x: 4 + CGFloat(i) * itemWidth, y: 4,
                             width: itemWidth, height: Self.itemHeight - 8)
            addSubview(l)
        }
        applySelection()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 依觸點（本視圖座標的 x）更新選中項
    func updateSelection(forX x: CGFloat) {
        let idx = max(0, min(itemLabels.count - 1, Int((x - 4) / itemWidth)))
        if idx != selectedIndex {
            selectedIndex = idx
            applySelection()
        }
    }

    private func applySelection() {
        for (i, l) in itemLabels.enumerated() {
            let selected = i == selectedIndex
            l.backgroundColor = selected ? KeyboardTheme.bubbleSelectedBackground : .clear
            l.textColor = selected ? KeyboardTheme.bubbleTextSelected : KeyboardTheme.bubbleTextUnselected
        }
    }
}
