import SwiftUI

/// ⚙ 面板 — 點工具列齒輪後蓋在鍵面區展開：把全部 ,, 指令做成可點的動作鈕
/// （不必記指令、不必打字），外加「開啟設定」連結（iOS 18 起鍵盤 extension
/// 只剩使用者親點 SwiftUI Link 這條開 URL 的路）。SwiftUI runtime 約 10MB，
/// 只在首次展開此面板時才載入。
struct SettingsPanelView: View {
    /// 執行 ,, 指令（傳不含 ,, 前綴的指令名）
    var onCommand: (String) -> Void
    var onDismiss: () -> Void
    /// 「開啟設定」— Link 的系統路徑之外，再交給 controller 多試幾條路（見 openContainerApp）
    var onOpenSettings: (URL) -> Void

    static let settingsURL = URL(string: "ohmybias://settings")!

    /// 一顆動作鈕：顯示名稱＋對應指令（指令當副標，順便記住鍵盤打法）
    private struct Command: Identifiable {
        let id: String        // 指令名（不含 ,,）
        let label: String
        var destructive = false
        init(_ id: String, _ label: String, destructive: Bool = false) {
            self.id = id; self.label = label; self.destructive = destructive
        }
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
            Command("rs", "重置字頻", destructive: true),
        ]),
    ]

    /// 破壞性指令需點兩次 — 第一次亮紅字提示，再點才執行
    @State private var pendingDestructive: String?

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
                Link(destination: Self.settingsURL) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                        Text("開啟設定")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .frame(height: 40)
                    .padding(.horizontal, 16)
                    .background(Color(KeyboardTheme.keySystem))
                    .foregroundColor(Color(KeyboardTheme.textSystem))
                    .cornerRadius(KeyboardTheme.cornerRadius)
                }
                // 保留 Link 原本的系統路徑（.systemAction，iOS 18–26 實測可用），
                // 同時讓 controller 走 extensionContext.open 等其他路 — iOS 27 起系統路徑不通
                .environment(\.openURL, OpenURLAction { url in
                    onOpenSettings(url)
                    return .systemAction
                })
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .background(Color(KeyboardTheme.panelRightBackground))
    }

    private func button(for command: Command) -> some View {
        let isPending = pendingDestructive == command.id
        return Button {
            if command.destructive && !isPending {
                pendingDestructive = command.id
                return
            }
            pendingDestructive = nil
            onCommand(command.id)
        } label: {
            VStack(spacing: 1) {
                Text(isPending ? "再點一次確認" : command.label)
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
            .foregroundColor(command.destructive ? .red : Color(KeyboardTheme.textSystem))
            .cornerRadius(KeyboardTheme.cornerRadius)
        }
    }
}
