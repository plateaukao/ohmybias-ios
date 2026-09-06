import SwiftUI

/// 自訂十格工具列；覆寫只存於偏好，清除後立即回到皮膚定義。
struct ToolbarSettingsView: View {
    @State private var slots = Array(repeating: ToolbarItems.placeholder, count: ToolbarItems.slotCount)
    @State private var selected = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("工具列（10 格）")
                        .font(.headline)
                Text("點選一格，再從下方選擇圖示。空白佔位會保留空格；變更在下次顯示鍵盤時生效。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(slots.indices, id: \.self) { index in
                        Button {
                            selected = index
                        } label: {
                            ToolbarGlyph(id: slots[index], compact: true)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(index == selected ? Color.accentColor.opacity(0.18) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7)
                                    .stroke(index == selected ? Color.accentColor : .secondary.opacity(0.45),
                                            lineWidth: index == selected ? 2 : 1))
                        }
                        .accessibilityLabel("第 \(index + 1) 格：\(ToolbarItems.definition(for: slots[index])?.label ?? "空白佔位")")
                        .buttonStyle(.plain)
                    }
                }
                Text(OhMyBiasPrefs.toolbarButtons == nil ? "目前：跟隨皮膚" : "目前：自訂")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if OhMyBiasPrefs.toolbarButtons != nil {
                    Button("還原皮膚工具列", role: .destructive) {
                        OhMyBiasPrefs.toolbarButtons = nil
                        loadSlots()
                    }
                    .buttonStyle(.bordered)
                }
            }

                VStack(alignment: .leading, spacing: 10) {
                    Text("可用圖示")
                        .font(.headline)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(ToolbarItems.selectable) { item in
                        Button {
                            slots[selected] = item.id
                            OhMyBiasPrefs.toolbarButtons = slots
                            selected = min(selected + 1, ToolbarItems.slotCount - 1)
                        } label: {
                            VStack(spacing: 4) {
                                ToolbarGlyph(id: item.id, compact: false)
                                    .frame(height: 26)
                                Text(item.label)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity, minHeight: 60)
                        }
                        .accessibilityLabel(item.label)
                        .buttonStyle(.plain)
                    }
                }
            }
            }
            .padding(16)
        }
        .navigationTitle("自訂工具列")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadSlots)
    }

    private func loadSlots() {
        let current = SkinSettings.shared.toolbarButtons
        slots = (0..<ToolbarItems.slotCount).map {
            current.indices.contains($0) ? current[$0] : ToolbarItems.placeholder
        }
    }
}

private struct ToolbarGlyph: View {
    let id: Int
    let compact: Bool

    var body: some View {
        let item = ToolbarItems.definition(for: id)
        Group {
            if let icon = item?.icon {
                Image(systemName: icon)
                    .font(.system(size: compact ? 16 : 21, weight: .medium))
            } else {
                Text(item?.text ?? "·")
                    .font(.system(size: compact ? 16 : 20))
            }
        }
        .foregroundStyle(item == nil ? Color.secondary.opacity(0.5) : Color.primary)
    }
}
