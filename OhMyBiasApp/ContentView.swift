import SwiftUI
import UniformTypeIdentifiers

/// 鍵盤外觀編輯器網站（plateaukao/ohmybias-skin — 匯出 .cskin 後回本頁匯入）
private let skinDesignerURL = URL(string: "https://plateaukao.github.io/ohmybias-skin/")!

struct ContentView: View {
    /// 兩種匯入共用同一個 .fileImporter — 同一個 view 掛兩個 .fileImporter 時只有最後一個
    /// 會彈出（Apple DTS 承認的 SwiftUI 限制）。舊版 liu.cin 的 importer 排在皮膚的前面，
    /// 「匯入 liu.cin」點了就是沒反應。
    private enum ImportKind { case cin, skin }
    @State private var showImporter = false
    @State private var pendingImport: ImportKind = .cin
    @State private var importing = false
    @State private var tableStatus = ""
    @State private var importMessage: String?
    @State private var skinStatus = ""
    @State private var skinMessage: String?
    @State private var pendingSkinJSON: Data?
    @State private var pendingSkinName = ""
    @State private var showSkinApplyConfirm = false

    @AppStorage("suggestEnabled", store: OhMyBiasPrefs.defaults) private var suggestEnabled = true
    @AppStorage("autoCommit", store: OhMyBiasPrefs.defaults) private var autoCommit = false
    @AppStorage("overflowAutoCommit", store: OhMyBiasPrefs.defaults) private var overflowAutoCommit = false
    @AppStorage("fuzzyMatch", store: OhMyBiasPrefs.defaults) private var fuzzyMatch = true
    @AppStorage("showCodeHint", store: OhMyBiasPrefs.defaults) private var showCodeHint = false
    @AppStorage("punctuationPairing", store: OhMyBiasPrefs.defaults) private var punctuationPairing = true
    @AppStorage("hapticFeedback", store: OhMyBiasPrefs.defaults) private var hapticFeedback = true
    @AppStorage("uppercaseLettersInChinese", store: OhMyBiasPrefs.defaults) private var uppercaseLettersInChinese = false
    @AppStorage("homophoneMultiReading", store: OhMyBiasPrefs.defaults) private var homophoneMultiReading = false
    @AppStorage("keyboardHeightScale", store: OhMyBiasPrefs.defaults) private var keyboardHeightScale = 1.0

    var body: some View {
        NavigationStack {
            Form {
                Section("啟用鍵盤") {
                    Text("設定 → 一般 → 鍵盤 → 鍵盤 → 新增鍵盤 → OhMyBias")
                        .font(.footnote)
                    Button("打開設定") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section("字表") {
                    if tableStatus.isEmpty {
                        Text("尚未匯入 liu.cin — 鍵盤無法輸出中文")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    } else {
                        Text(tableStatus).font(.footnote)
                    }
                    Button("匯入 liu.cin") { pendingImport = .cin; showImporter = true }
                        .disabled(importing)
                    if let msg = importMessage {
                        Text(msg).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("皮膚") {
                    Text(skinStatus).font(.footnote)
                    Link("鍵盤外觀編輯器（網頁）", destination: skinDesignerURL)
                    Button("匯入皮膚（.cskin）") { pendingImport = .skin; showImporter = true }
                    if SkinSettings.shared.isImported {
                        Button("還原內建皮膚", role: .destructive) { resetSkin() }
                    }
                    if let msg = skinMessage {
                        Text(msg).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("聯想") {
                    Toggle("聯想詞（萌典詞組）", isOn: $suggestEnabled)
                    NavigationLink("常用語設定") {
                        UserPhrasesEditor()
                    }
                }

                Section("輸入") {
                    Toggle("唯一候選自動送出", isOn: $autoCommit)
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("滿碼頂字上屏", isOn: $overflowAutoCommit)
                        Text("滿碼後續打自動送出首選。開啟時 weekly 這類前四碼恰為字根的英文字無法直通")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("相鄰鍵模糊比對", isOn: $fuzzyMatch)
                    Toggle("送字後顯示字根提示", isOn: $showCodeHint)
                    Toggle("成對標點自動補右半", isOn: $punctuationPairing)
                    Toggle("按鍵觸覺回饋", isOn: $hapticFeedback)
                    Toggle("米模式字母鍵顯示大寫", isOn: $uppercaseLettersInChinese)
                    Toggle("同音字含罕見讀音", isOn: $homophoneMultiReading)
                    // 鍵盤高度滑桿（大螢幕手機可調大；重開鍵盤生效）— 同 Android 版
                    VStack(alignment: .leading, spacing: 4) {
                        Text("鍵盤高度：\(Int((keyboardHeightScale * 100).rounded()))%（85–140，重開鍵盤生效）")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Slider(value: $keyboardHeightScale, in: 0.85...1.40, step: 0.01)
                    }
                }

                Section("指令速查") {
                    Text("""
                    ,,T 繁體  ,,S 簡體  ,,J 日文
                    ,,SP 速成  ,,SL 慢打
                    ,,TS 繁→簡  ,,ST 簡→繁
                    ,,ZH 注音查碼  ,,TO 同音字
                    ,,PYS 拼音(簡)  ,,PYT 拼音(繁)
                    ,,SG 聯想開關  ,,C 目前模式
                    ,,PIN 固定排序  ,,UNPINx 解除
                    ,,RS 重置字頻  ,,RL 重載字表
                    ,,V 貼上純文字  ,,VT 簡→繁  ,,VS 繁→簡

                    以上指令在鍵盤工具列 ⚙ 也都有對應按鈕，可直接點選
                    """)
                    .font(.system(.footnote, design: .monospaced))
                }
            }
            .navigationTitle("OhMyBias 米")
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: pendingImport == .skin ? Self.skinTypes : Self.cinTypes,
                      allowsMultipleSelection: false) { result in
            switch pendingImport {
            case .cin: handleImport(result)
            case .skin: handleSkinImport(result)
            }
        }
        .onAppear {
            refreshTableStatus()
            refreshSkinStatus()
        }
        // 檔案 app／瀏覽器點 .cskin 開啟本 app（Info.plist 文件類型宣告）—
        // 非使用者主動選檔，先顯示皮膚名稱確認再套用（同 Android 版）
        .onOpenURL { handleOpenedFile($0) }
        .alert("套用皮膚", isPresented: $showSkinApplyConfirm) {
            Button("套用") {
                if let json = pendingSkinJSON { applySkinJSON(json) }
                pendingSkinJSON = nil
            }
            Button("取消", role: .cancel) { pendingSkinJSON = nil }
        } message: {
            Text("要套用皮膚「\(pendingSkinName)」嗎？\n（會取代目前的皮膚，重開鍵盤生效）")
        }
    }

    private static let cinTypes: [UTType] = [.plainText, .data]
    private static let skinTypes: [UTType] = [UTType(filenameExtension: "cskin") ?? .zip, .zip, .data]

    /// 讀取選檔器交回的檔案 — 走 NSFileCoordinator。iCloud Drive 尚未下載到本機的檔案、
    /// 第三方檔案 provider（Google Drive、Dropbox…）的檔案，直接 copyItem／Data(contentsOf:)
    /// 會拿到「檔案不存在」或「沒有權限」；協調讀取才會觸發下載／實體化。
    private static func readCoordinated(_ url: URL) throws -> Data {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        var coordError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            result = Result { try Data(contentsOf: readURL) }
        }
        if let e = coordError { throw e }
        return try result.get()
    }

    // MARK: - 皮膚匯入（.cskin = zip，取其中 jsonnet/settings.json 的配置層）

    /// 讀出 .cskin（zip）內的 settings.json；非 zip 或缺檔回 nil
    private func readSkinSettingsJSON(_ url: URL) -> Data? {
        guard let zipData = try? Self.readCoordinated(url) else { return nil }
        return ZipReader.extractFirst(named: "jsonnet/settings.json", from: zipData)
            ?? ZipReader.extractFirst(named: "settings.json", from: zipData)
    }

    private func applySkinJSON(_ json: Data) {
        do {
            try json.write(to: URL(fileURLWithPath: SkinSettings.settingsPath))
            SkinSettings.shared.reload()
            skinMessage = SkinSettings.shared.isImported
                ? "已套用「\(SkinSettings.shared.skinName)」— 重開鍵盤生效"
                : "settings.json 格式無法解析"
            refreshSkinStatus()
        } catch {
            skinMessage = "匯入失敗：\(error.localizedDescription)"
        }
    }

    /// SAF 式選檔匯入：直接套用（使用者已在選檔時表達意圖）
    private func handleSkinImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard let json = readSkinSettingsJSON(url) else {
            skinMessage = "找不到 settings.json — 請確認是有效的 .cskin 檔"; return
        }
        applySkinJSON(json)
    }

    /// 點 .cskin 檔開啟本 app — 解出皮膚名稱、確認框後才套用
    private func handleOpenedFile(_ url: URL) {
        guard url.isFileURL, url.pathExtension.lowercased() == "cskin" else { return }
        guard let json = readSkinSettingsJSON(url) else {
            skinMessage = "找不到 settings.json — 請確認是有效的 .cskin 檔"; return
        }
        let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
        let name = (root?["skinInfo"] as? [String: Any])?["name"] as? String
        pendingSkinName = (name?.isEmpty == false) ? name! : "未命名皮膚"
        pendingSkinJSON = json
        showSkinApplyConfirm = true
    }

    private func resetSkin() {
        try? FileManager.default.removeItem(atPath: SkinSettings.settingsPath)
        SkinSettings.shared.reload()
        skinMessage = "已還原內建皮膚 — 重開鍵盤生效"
        refreshSkinStatus()
    }

    private func refreshSkinStatus() {
        SkinSettings.shared.reload()
        skinStatus = "目前皮膚：\(SkinSettings.shared.skinName)"
    }

    /// liu.cin 動輒數 MB、來源又可能是雲端硬碟（下載時間不定）— 讀取＋編譯放背景執行緒
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importMessage = "選檔失敗：\(error.localizedDescription)"
            return
        case .success(let urls):
            guard let url = urls.first else { return }
            importing = true
            importMessage = "匯入中…"
            DispatchQueue.global(qos: .userInitiated).async {
                let message = Self.importCin(from: url)
                DispatchQueue.main.async {
                    importing = false
                    importMessage = message
                    refreshTableStatus()
                }
            }
        }
    }

    /// 讀取＋編譯都到暫存檔，兩者成功才換掉現用的 liu.cin／liu.bin —
    /// 中途失敗（讀到一半斷線、不是有效 .cin）不動現有字表。回傳給使用者看的結果訊息。
    private static func importCin(from url: URL) -> String {
        let fm = FileManager.default
        let dir = AppConstants.sharedDir
        let tmpCin = dir + "/liu.cin.importing"
        let tmpBin = dir + "/liu.bin.importing"
        defer {
            try? fm.removeItem(atPath: tmpCin)
            try? fm.removeItem(atPath: tmpBin)
        }
        let data: Data
        do { data = try readCoordinated(url) }
        catch { return "無法讀取檔案：\(error.localizedDescription)\n（iCloud 雲端檔案請先在「檔案」app 裡點一下下載到本機）" }
        guard !data.isEmpty else { return "檔案是空的" }
        do { try data.write(to: URL(fileURLWithPath: tmpCin)) }
        catch { return "無法寫入暫存檔：\(error.localizedDescription)" }
        let count: Int
        do { count = try CINCompiler.compileDetailed(src: tmpCin, dst: tmpBin) }
        catch CINCompiler.CompileError.undecodable { return "無法辨識檔案編碼 — 支援 UTF-8、UTF-16、Big5" }
        catch CINCompiler.CompileError.noChardef { return "找不到 %chardef 字碼區段 — 請確認是有效的 .cin 檔" }
        catch { return "編譯失敗：\(error.localizedDescription)" }
        do {
            try replace(AppConstants.cinPath, with: tmpCin)
            try replace(dir + "/liu.bin", with: tmpBin)
        } catch { return "無法寫入字表：\(error.localizedDescription)" }
        // 字表到手就回嘸蝦米 — 匯入前打不出中文而切去的英文模式不該延續到有字表之後
        OhMyBiasPrefs.resetToChineseMode()
        return "已編譯 \(count) 個字碼"
    }

    /// 原子換檔：目的地已存在就 replaceItemAt，否則直接搬過去
    private static func replace(_ dst: String, with src: String) throws {
        let fm = FileManager.default
        let dstURL = URL(fileURLWithPath: dst), srcURL = URL(fileURLWithPath: src)
        if fm.fileExists(atPath: dst) {
            _ = try fm.replaceItemAt(dstURL, withItemAt: srcURL)
        } else {
            try fm.moveItem(at: srcURL, to: dstURL)
        }
    }

    private func refreshTableStatus() {
        let table = CINTable()
        table.reload()
        if table.isEmpty {
            tableStatus = ""
        } else {
            let name = table.cinName.isEmpty ? "字表" : table.cinName
            tableStatus = "已載入：\(name)（最長碼 \(table.maxCodeLength)）"
        }
    }
}

/// 常用語設定 — 一列一詞：詞 ＋ 自訂組字碼；組字碼即時對照字表：
/// 未被使用 → 打碼直接出本詞；已有候選 → 本詞排在既有候選之後（列出撞到的字）。
/// 組字碼欄用 asciiCapable 鍵盤型別 — OhMyBias 鍵盤對這類欄位走暫時英文直通，打碼才不會被組成中文。
/// 離開頁面即存檔（同原本對話框的行為）；鍵盤 extension 下次出現時比對檔案時間重套捷徑。
struct UserPhrasesEditor: View {
    /// 列的穩定身分 — 內容可編輯，id 不隨文字變
    private struct Row: Identifiable {
        let id = UUID()
        var phrase: String
        var code: String
    }

    @State private var rows: [Row] = []
    @State private var loaded = false
    /// 對照用字表 — 只用 lookup（字表本身的候選），不含捷徑
    @State private var table: CINTable? = nil
    @FocusState private var focusedRow: UUID?

    var body: some View {
        List {
            Section {
                Text("常用語顯示於鍵盤 ♥ 面板；打詞首字也會出現聯想。\n設了「組字碼」就能直接用鍵盤打碼叫出，不必開面板。碼已被字表使用時，本詞排在既有候選之後。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach($rows) { $row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            TextField("常用語", text: $row.phrase)
                                .focused($focusedRow, equals: row.id)
                            TextField("組字碼", text: $row.code)
                                .keyboardType(.asciiCapable)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 96)
                                .onChange(of: row.code) { _, v in
                                    let lower = v.lowercased()
                                    if lower != v { row.code = lower }
                                    if lower.count > 8 { row.code = String(lower.prefix(8)) }
                                }
                        }
                        if let (text, color) = status(for: row) {
                            Text(text).font(.caption).foregroundStyle(color)
                        }
                    }
                }
                .onDelete { rows.remove(atOffsets: $0) }
                Button {
                    let r = Row(phrase: "", code: "")
                    rows.append(r)
                    focusedRow = r.id
                } label: {
                    Label("新增常用語", systemImage: "plus")
                }
            }
        }
        .navigationTitle("常用語設定")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            UserPhrases.shared.reload()
            rows = UserPhrases.shared.entries.map { Row(phrase: $0.phrase, code: $0.code ?? "") }
            if rows.isEmpty { rows = [Row(phrase: "", code: "")] }
            let t = CINTable(); t.reload(); table = t
        }
        .onDisappear { save() }
    }

    private func entries() -> [UserPhrases.Entry] {
        rows.compactMap { r in
            let p = r.phrase.trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty else { return nil }
            let c = r.code.trimmingCharacters(in: .whitespaces).lowercased()
            // 不合法的碼不存（列表上已用紅字提示）
            return UserPhrases.Entry(p, UserPhrases.isValidCode(c) ? c : nil)
        }
    }

    private func save() {
        UserPhrases.shared.save(entries())
    }

    /// 組字碼狀態列（nil = 沒設碼不顯示）
    private func status(for row: Row) -> (String, Color)? {
        let code = row.code.trimmingCharacters(in: .whitespaces).lowercased()
        if code.isEmpty { return nil }
        if !UserPhrases.isValidCode(code) {
            return (code.hasPrefix(",,") ? "✗ ,, 是指令前綴，不能當組字碼" : "✗ 只能用 a–z 及 , . ' [ ]", .red)
        }
        // 同碼的其他常用語 — 都會列出（依列表順序）
        let sameCode = rows.filter { $0.id != row.id && $0.code.trimmingCharacters(in: .whitespaces).lowercased() == code }
            .map { $0.phrase.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let existing = (table?.isEmpty ?? true) ? [] : (table?.lookup(code) ?? [])
        var text: String
        var color: Color
        if existing.isEmpty {
            text = "✓ 未被使用 — 打「\(code)」直接出現本詞"
            color = .green
        } else {
            text = "⚠ 已有候選 " + existing.prefix(6).joined(separator: " ")
            if existing.count > 6 { text += " …（共 \(existing.count) 個）" }
            text += " — 本詞排在其後"
            color = .orange
        }
        if !sameCode.isEmpty {
            text += "；與「" + sameCode.joined(separator: "」「") + "」同碼，都會列出"
        }
        return (text, color)
    }
}
