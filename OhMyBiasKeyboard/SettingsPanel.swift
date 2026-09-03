import SwiftUI

/// ⚙ 面板 — 點工具列齒輪後蓋在鍵面區展開：把全部 ,, 指令做成可點的動作鈕
/// （不必記指令、不必打字）。SwiftUI runtime 約 10MB，只在首次展開此面板時才載入。
///
/// 原本右下角有「開啟設定」連結（SwiftUI Link 是 iOS 18 起鍵盤 extension 唯一能開 URL 的路），
/// iOS 27 起連那條也被封、按了只會跳「無法自動開啟」— 已移除；設定請從主畫面開容器 app。
struct SettingsPanelView: View {
    /// 執行 ,, 指令（傳不含 ,, 前綴的指令名）
    var onCommand: (String) -> Void
    var onDismiss: () -> Void

    /// 一顆動作鈕：顯示名稱＋對應指令（指令當副標，順便記住鍵盤打法）
    private struct Command: Identifiable {
        let id: String        // 指令名（不含 ,,）
        let label: String
        init(_ id: String, _ label: String) { self.id = id; self.label = label }
    }

    private struct Group: Identifiable {
        let id: String
        let commands: [Command]
    }

    private static let groups: [Group] = [
        Group(id: "輸入模式", commands: [
            Command("t", "繁體"), Command("s", "簡體"), Command("j", "日文"),
            Command("sp", "速成"), Command("sl", "慢打"),
            Command("ts", "繁→簡"), Command("st", "簡→繁"),
        ]),
        Group(id: "查碼模式", commands: [
            Command("zh", "注音"), Command("to", "同音字"),
            Command("pys", "拼音簡"), Command("pyt", "拼音繁"),
        ]),
        Group(id: "剪貼簿", commands: [
            Command("v", "貼上純文字"), Command("vt", "貼上簡→繁"), Command("vs", "貼上繁→簡"),
        ]),
        Group(id: "其他", commands: [
            Command("sg", "聯想開關"), Command("c", "目前模式"),
            Command("pin", "固定排序"), Command("rl", "重載字表"),
        ]),
    ]

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 6)]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Self.groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.id)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(KeyboardTheme.textSub))
                            LazyVGrid(columns: columns, spacing: 6) {
                                ForEach(group.commands) { command in
                                    button(for: command)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            HStack(spacing: 10) {
                Button(action: onDismiss) {
                    Text("返回")
                        .font(.system(size: 16))
                        .frame(width: 72, height: 40)
                        .background(Color(KeyboardTheme.keySystem))
                        .foregroundColor(Color(KeyboardTheme.textSystem))
                        .cornerRadius(KeyboardTheme.cornerRadius)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .background(Color(KeyboardTheme.panelRightBackground))
    }

    private func button(for command: Command) -> some View {
        Button {
            onCommand(command.id)
        } label: {
            VStack(spacing: 1) {
                Text(command.label)
                    .font(.system(size: 15))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(",,\(command.id.uppercased())")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(KeyboardTheme.textSub))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(Color(KeyboardTheme.keySystem))
            .foregroundColor(Color(KeyboardTheme.textSystem))
            .cornerRadius(KeyboardTheme.cornerRadius)
        }
    }
}
