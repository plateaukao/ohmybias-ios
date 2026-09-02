import Foundation

// Minimal test harness（與 Yabomish 相同的 check/checkEqual 形式）
var passed = 0
var failed = 0

func check(_ condition: Bool, _ msg: String = "", file: String = #file, line: Int = #line) {
    if condition { passed += 1 }
    else { failed += 1; print("FAIL [\(file):\(line)] \(msg)") }
}

func checkEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: String = #file, line: Int = #line) {
    if a == b { passed += 1 }
    else { failed += 1; print("FAIL [\(file):\(line)] \(msg) — got \(a), expected \(b)") }
}

// === Test doubles ===

struct MockPrefs: IMEPreferences {
    var suggestEnabled = true
    var autoCommit = false
    var overflowAutoCommit = false
    var fuzzyMatch = false
    var showCodeHint = false
    var suggestStrategy = "general"
    var wordCorpus = "moedict"
    var charSuggest = false
    var regionVariant = "tw"
    func domainEnabled(_ key: String) -> Bool { true }
    func domainPriority(_ key: String) -> Int { 0 }
    var punctuationPairing = true
}

// === Fixtures ===

let fixtureCIN = """
%gen_inp
%ename Test
%cname 測試表
%selkey 1234567890
%chardef begin
a 日
aa 昌
ab 明
b 月
ba 朋
hj 手
hj 乎
zb 「
zzzz 龘
%chardef end
"""

func makeFixtureTable() -> CINTable {
    let path = NSTemporaryDirectory() + "ohmybias_test_\(UUID().uuidString).cin"
    try! fixtureCIN.write(toFile: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: path) }
    let table = CINTable()
    table.load(cinPath: path)
    return table
}

func makeEngine(prefs: MockPrefs = MockPrefs()) -> (InputEngine, MockEngineDelegate) {
    let engine = InputEngine(cinTable: makeFixtureTable(),
                             suggestionEngine: SuggestionEngine(prefs: prefs),
                             prefs: prefs)
    let mock = MockEngineDelegate()
    engine.delegate = mock
    return (engine, mock)
}

// === Tests ===

func testHarness() {
    check(true, "true is true")
    checkEqual("abc", "abc", "string equality")
}

func testCINCompileRoundtrip() {
    let table = makeFixtureTable()
    check(!table.isEmpty, "fixture table loads")
    checkEqual(table.cinName, "測試表", "cname parsed")
    checkEqual(table.lookup("a"), ["日"], "single code lookup")
    checkEqual(table.lookup("ab"), ["明"], "two-key code lookup")
    checkEqual(Set(table.lookup("hj")), Set(["手", "乎"]), "multi-candidate code")
    check(table.hasPrefix("a"), "hasPrefix a")
    check(!table.hasPrefix("q"), "no prefix q")
    let next = table.validNextKeys(after: "a")
    checkEqual(next, Set(["a", "b"]), "valid next keys after a")
    checkEqual(Set(table.wildcardLookup("a*")), Set(["昌", "明"]), "wildcard a*")
    check(table.reverseLookup("明").contains("ab"), "reverse lookup")
}

/// 匯入來源五花八門：Big5 的舊版 liu.cin、記事本另存的 UTF-8 BOM／UTF-16、CRLF、tab 分隔的指令列
func testCINCompileEncodings() {
    let cin = "%cname\t編碼表\r\n%selkey 1234567890\r\n%chardef  begin\r\na\t日\r\nab 明\r\n%chardef end\r\n"
    let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.big5.rawValue)))
    var utf8bom = Data([0xEF, 0xBB, 0xBF]); utf8bom.append(cin.data(using: .utf8)!)
    let variants: [(String, Data)] = [
        ("utf8+bom+crlf", utf8bom),
        ("utf16+bom", cin.data(using: .utf16)!),
        ("big5", cin.data(using: big5)!),
    ]
    for (label, data) in variants {
        checkEqual(CINCompiler.decode(data), cin, "\(label): decode round-trips")
        let src = NSTemporaryDirectory() + "ohmybias_enc_\(UUID().uuidString).cin"
        let dst = src + ".bin"
        defer { try? FileManager.default.removeItem(atPath: src); try? FileManager.default.removeItem(atPath: dst) }
        try! data.write(to: URL(fileURLWithPath: src))
        checkEqual(CINCompiler.compile(src: src, dst: dst), 2, "\(label): 2 codes compiled")
        let table = CINTable(); table.load(path: src)
        checkEqual(table.cinName, "編碼表", "\(label): cname via tab-separated directive")
        checkEqual(table.lookup("ab"), ["明"], "\(label): lookup")
    }
    // 沒有 %chardef 區段 → 具體錯誤而不是靜默 0
    let empty = NSTemporaryDirectory() + "ohmybias_enc_\(UUID().uuidString).cin"
    defer { try? FileManager.default.removeItem(atPath: empty) }
    try! "%cname x\n".write(toFile: empty, atomically: true, encoding: .utf8)
    do { _ = try CINCompiler.compileDetailed(src: empty, dst: empty + ".bin"); check(false, "noChardef should throw") }
    catch CINCompiler.CompileError.noChardef { check(true, "noChardef thrown") }
    catch { check(false, "unexpected error \(error)") }
    do { _ = try CINCompiler.compileDetailed(src: empty + ".missing", dst: empty + ".bin"); check(false, "unreadable should throw") }
    catch CINCompiler.CompileError.unreadable { check(true, "unreadable thrown") }
    catch { check(false, "unexpected error \(error)") }
}

func testEngineComposeAndCommit() {
    let (engine, mock) = makeEngine()
    engine.handleLetter("a")
    checkEqual(engine.composing, "a", "composing after letter")
    check(mock.candidateUpdates.last?.first == "日", "candidate 日 shown")
    engine.handleSpace()
    checkEqual(mock.commits.last, "日", "space commits first candidate")
    checkEqual(engine.composing, "", "composing cleared after commit")
}

func testEngineCommitComposingRaw() {
    // 有候選但使用者要英文單字：點組字碼原樣上屏（不帶尾隨空格、不記字頻）
    let (engine, mock) = makeEngine()
    engine.handleLetter("a")
    check(!engine.currentCandidates.isEmpty, "有候選")
    engine.commitComposingRaw()
    checkEqual(mock.commits.last, "a", "原樣送出字母")
    checkEqual(engine.composing, "", "送出後清空 composing")
    check(engine.currentCandidates.isEmpty, "送出後清空候選")
    let commitCount = mock.commits.count
    engine.commitComposingRaw()
    checkEqual(mock.commits.count, commitCount, "composing 空時無動作")
}

func testEngineEnglishPassthrough() {
    let (engine, mock) = makeEngine()
    // fixture 表 maxCodeLength=4（CINTable 下限）— "hello" 無候選且超長，應續收不清除
    for ch in "hello" { engine.handleLetter(String(ch)) }
    checkEqual(engine.composing, "hello", "無候選時續打不清除")
    check(engine.currentCandidates.isEmpty, "英文直通中無候選")
    engine.handleSpace()
    checkEqual(mock.commits.last, "hello ", "空白鍵原樣送出字串＋尾隨空格")
    checkEqual(engine.composing, "", "送出後清空 composing")
    // 送出後 composing 已空，再次 handleSpace 不應動作（controller 層會直接輸出空白）
    let commitCount = mock.commits.count
    engine.handleSpace()
    checkEqual(mock.commits.count, commitCount, "composing 空時 handleSpace 無動作")
}

func testEngineOverflowAutoCommit() {
    // 預設關：滿碼有候選（zzzz=龘）再打第五鍵不頂字 — 續打成 raw、空白原樣送出
    // （weekly 情境：前四碼恰為有效字根的英文字也要能直通）
    let (engine, mock) = makeEngine()
    for ch in "zzzzz" { engine.handleLetter(String(ch)) }
    checkEqual(engine.composing, "zzzzz", "滿碼有候選仍續打不頂字")
    check(engine.currentCandidates.isEmpty, "超長字串無候選")
    engine.handleSpace()
    checkEqual(mock.commits.last, "zzzzz ", "空白鍵原樣送出＋尾隨空格")

    // 開啟頂字上屏：滿碼再打一鍵送出首選、開始下一字
    var prefs = MockPrefs(); prefs.overflowAutoCommit = true
    let (engine2, mock2) = makeEngine(prefs: prefs)
    for ch in "zzzzz" { engine2.handleLetter(String(ch)) }
    checkEqual(mock2.commits.last, "龘", "頂字上屏送出 zzzz 首選")
    checkEqual(engine2.composing, "z", "頂字後以新鍵開始下一字")
}

func testEngineBackspaceAndEscape() {
    let (engine, mock) = makeEngine()
    engine.handleLetter("a")
    engine.handleLetter("b")
    checkEqual(engine.composing, "ab", "composing ab")
    engine.handleBackspace()
    checkEqual(engine.composing, "a", "backspace drops last key")
    engine.handleEscape()
    checkEqual(engine.composing, "", "escape clears composing")
    check(mock.commits.isEmpty, "nothing committed")
}

func testEngineVRSF() {
    let (engine, mock) = makeEngine()
    engine.handleLetter("h")
    engine.handleLetter("j")
    check(engine.currentCandidates.count >= 2, "hj has two candidates")
    let second = engine.currentCandidates[1]
    check(engine.handleVRSF("v"), "VRSF v selects 2nd candidate")
    checkEqual(mock.commits.last, second, "v committed second candidate")
}

func testEnginePunctuationPairing() {
    let (engine, mock) = makeEngine()
    engine.handleLetter("z")
    engine.handleLetter("b")
    engine.handleSpace()
    checkEqual(mock.commitPairs.count, 1, "paired punctuation committed as pair")
    check(mock.commitPairs.last?.0 == "「" && mock.commitPairs.last?.1 == "」", "「」 pair")
}

/// 符號鍵不經組字流程，改問 pairedRight —— 半形括號/雙引號也要配，單引號不配
func testEnginePairedRight() {
    let (engine, _) = makeEngine()
    checkEqual(engine.pairedRight("（"), "）", "（ pairs")
    checkEqual(engine.pairedRight("【"), "】", "【 pairs")
    checkEqual(engine.pairedRight("("), ")", "half-width ( pairs")
    checkEqual(engine.pairedRight("["), "]", "half-width [ pairs")
    checkEqual(engine.pairedRight("{"), "}", "half-width { pairs")
    checkEqual(engine.pairedRight("\""), "\"", "double quote pairs")
    checkEqual(engine.pairedRight("'"), nil, "single quote does not pair")
    checkEqual(engine.pairedRight("）"), nil, "right half does not pair")
    checkEqual(engine.pairedRight("（）"), nil, "multi-char does not pair")

    var offPrefs = MockPrefs()
    offPrefs.punctuationPairing = false
    let (offEngine, _) = makeEngine(prefs: offPrefs)
    checkEqual(offEngine.pairedRight("（"), nil, "pairing off → no right half")
}

func testEngineCommaCommandUnknown() {
    let (engine, mock) = makeEngine()
    engine.handleLetter(",")
    engine.handleLetter(",")
    engine.handleLetter("q")
    engine.handleLetter("q")
    engine.handleSpace()
    check(mock.toasts.last?.contains("未知命令") == true, "unknown ,, command toast")
}

func testEngineModeSwitch() {
    let (engine, mock) = makeEngine()
    engine.handleLetter(",")
    engine.handleLetter(",")
    engine.handleLetter("s")
    engine.handleSpace()
    checkEqual(engine.inputMode, .s, ",,S switches to 簡中")
    checkEqual(mock.toasts.last, "簡中", "mode toast")
    engine.switchToMode("t")
    checkEqual(engine.inputMode, .t, "switchToMode back to 繁中")
}

func testEngineSetEnglishMode() {
    let (engine, mock) = makeEngine()
    check(!engine.isEnglishMode, "初始為中文模式")
    engine.setEnglishMode(true)
    check(engine.isEnglishMode, "setEnglishMode(true) 進入英文模式")
    check(mock.toasts.isEmpty, "還原模式不顯示 toast")
    engine.setEnglishMode(true)
    check(engine.isEnglishMode, "重複設定為冪等")
    engine.setEnglishMode(false)
    check(!engine.isEnglishMode, "setEnglishMode(false) 回中文模式")
    engine.toggleEnglishMode()
    check(engine.isEnglishMode, "toggle 後為英文")
    check(mock.toasts.isEmpty, "中英切換不顯示 toast（鍵面已可見目前模式）")
}

func testSkinSettingsParse() {
    let json = """
    {"skinInfo": {"name": "蝦米輸入法", "author": "Ryan"},
     "toolbar": {"toolbarButtons": [1, 3, 9, 7, 16, 17, 8, 10, 13, 2]},
     "layout": {"keyboardLayout": "row", "spaceKeyLayout": "2", "longPressLayout": "1"},
     "swipe": {"globalEnabledFeatures": ["swipeUp", "longPress"]},
     "globalSettings": {"palette": {"light": {"bg": "#FFFFFFFF", "borderSize": 2},
                                    "dark": {"bg": "#000000FF"}},
                        "groups": {"lowercaseSize": 25}}}
    """.data(using: .utf8)!
    let skin = SkinSettings.shared
    skin.apply(jsonData: json)
    checkEqual(skin.skinName, "蝦米輸入法", "skinInfo.name")
    checkEqual(skin.toolbarButtons, [1, 3, 9, 7, 16, 17, 8, 10, 13, 2], "toolbarButtons")
    checkEqual(skin.keyboardLayout, "row", "keyboardLayout")
    checkEqual(skin.spaceKeyLayout, "2", "spaceKeyLayout")
    checkEqual(skin.longPressLayout, "1", "longPressLayout")
    check(skin.swipeUpEnabled && !skin.swipeDownEnabled, "swipe 全域開關")
    check(skin.longPressEnabled && !skin.showSwipeUpText, "longPress 開、角標關")
    checkEqual(skin.colorHex("bg", dark: false), "#FFFFFFFF", "light palette")
    checkEqual(skin.colorHex("bg", dark: true), "#000000FF", "dark palette")
    checkEqual(skin.paletteNumber("borderSize", dark: false), 2, "palette 數值")
    checkEqual(skin.fontSize("lowercaseSize", default: 23), 25, "字級 groups")
    checkEqual(skin.fontSize("systemSize", default: 16), 16, "字級 fallback")
    skin.reload()  // 還原預設，避免影響其他測試
    checkEqual(skin.toolbarButtons, SkinSettings.defaultToolbarButtons, "reload 還原內建預設")
}

func testSkinSettingsParseFlat() {
    // 新版 cskin 匯出器的扁平 schema（toolbarButtons/palette/groups 在頂層、滑動開關為布林）
    let json = """
    {"skinInfo": {"name": "蝦米輸入法", "author": "Ryan"},
     "spaceKeyLayout": "1",
     "handedness": "left",
     "enableSwipeUpActions": true, "enableSwipeDownActions": false,
     "enableLongPressActions": true, "showSwipeUpText": false, "showSwipeDownText": true,
     "toolbarButtons": [1, 3, 7, 0, 10, 5, 6, 0, 8, 2],
     "enableCustomColors": true,
     "palette": {"light": {"bg": "#D0D3DA01", "keySystem": "#979faf80"},
                 "dark": {"bg": "#000000"}},
     "groups": {"lowercaseSize": 17, "systemSize": 14}}
    """.data(using: .utf8)!
    let skin = SkinSettings.shared
    skin.apply(jsonData: json)
    checkEqual(skin.toolbarButtons, [1, 3, 7, 0, 10, 5, 6, 0, 8, 2], "扁平 toolbarButtons")
    checkEqual(skin.spaceKeyLayout, "1", "扁平 spaceKeyLayout")
    check(skin.swipeUpEnabled && !skin.swipeDownEnabled, "扁平滑動開關")
    check(skin.longPressEnabled && !skin.showSwipeUpText && skin.showSwipeDownText, "扁平角標開關")
    checkEqual(skin.colorHex("keySystem", dark: false), "#979faf80", "扁平 light palette")
    checkEqual(skin.colorHex("bg", dark: true), "#000000", "扁平 dark palette")
    checkEqual(skin.fontSize("lowercaseSize", default: 23), 17, "扁平 groups")
    skin.reload()  // 還原預設，避免影響其他測試
}

// === 聯想（基本詞組）tests ===

/// v2 資料表（ZYM2 / PYM2 / CFM2）讀取端 — 期望值與 Android DataBinsV2Test 相同（取自 v1 解析結果），
/// 涵蓋非 BMP 字（surrogate pair）、多讀音順序、拼音別名與內嵌、頻次同分、區塊差值鍵表的命中／未命中。
func testZhuyinLookupBins() {
    let zl = ZhuyinLookup()
    let ba = zl.charsForZhuyin("ㄅㄚ")
    checkEqual(ba.count, 15, "ㄅㄚ has 15 chars")
    checkEqual(Array(ba.prefix(5)), ["八", "巴", "吧", "扒", "芭"], "ㄅㄚ order")
    let bo2 = zl.charsForZhuyin("ㄅㄛˊ")
    checkEqual(bo2.count, 62, "ㄅㄛˊ has 62 chars")
    check(bo2.contains("\u{29C5A}"), "𩱚 (surrogate pair) kept as one char")
    check(bo2.allSatisfy { $0.unicodeScalars.count == 1 }, "every entry is one code point")
    check(zl.charsForZhuyin("ㄅㄨㄅㄨ").isEmpty, "unknown syllable → empty")

    let sorted = zl.sortByFreq(["龘", "我", "的", "A"])
    checkEqual(sorted, ["的", "我", "龘", "A"], "freq order 的 > 我 > 龘 > unknown")
    checkEqual(zl.sortByFreq(["㑳", "扦"]), ["㑳", "扦"], "equal freq keeps input order")
    checkEqual(zl.sortByFreq(["A", "\u{20089}"]), ["\u{20089}", "A"], "𠂉 U+20089 non-BMP has freq")

    MemoryBudget.bypassChecks = true
    let prev = OhMyBiasPrefs.homophoneMultiReading
    OhMyBiasPrefs.homophoneMultiReading = true
    let san = zl.lookup("三")
    checkEqual(san.map { $0.zhuyin }, ["ㄙㄢ", "ㄙㄚ", "ㄙㄢˋ"], "三 readings in stored order")
    check(san.allSatisfy { !$0.chars.contains("三") }, "homophones exclude self")
    checkEqual(zl.lookup("\u{20065}").map { $0.zhuyin }, ["ㄍㄨㄞˇ"], "𠁥 U+20065 non-BMP key via ext section")
    check(zl.lookup("A").isEmpty, "unknown char → no readings")
    check(zl.lookup("三三").isEmpty, "multi-char → no readings")
    OhMyBiasPrefs.homophoneMultiReading = prev

    checkEqual(zl.charsForPinyin("ba1"), ba, "pinyin alias → same list as ㄅㄚ")
    let yu2 = zl.charsForPinyin("yu2")
    checkEqual(yu2.count, 92, "yu2 inline list (ㄧㄡ+ㄩ merged)")
    checkEqual(Array(yu2.prefix(3)), ["由", "遊", "游"], "yu2 order")
    checkEqual(Array(zl.charsForPinyin("lv2").prefix(3)), ["驢", "閭", "櫚"], "lv → lü fallback")
    check(zl.charsForPinyin("zzz").isEmpty, "unknown pinyin → empty")
}

func testWikiCorpusPhrases() {
    let corpus = WikiCorpus.shared
    check(corpus.domainBinCount == 1, "phrases.bin loaded")
    let after日 = corpus.suggestDomainTerms(prefix: "日", limit: 5)
    check(!after日.isEmpty, "single-char 日 has phrase suggestions")
    check(after日.allSatisfy { !$0.hasPrefix("日") }, "single-char suggestions are remainders")
    let comp = corpus.phraseCompletions(for: "明天", limit: 3)
    // 明天 可能無更長詞 — 只驗證回傳為餘字形式
    check(comp.allSatisfy { !$0.hasPrefix("明天") }, "completions are remainders")
    let wc = corpus.suggestWordCorpus(prefix: "臺灣", limit: 5)
    check(!wc.isEmpty, "臺灣 has word-corpus completions")
    // PHM2：首字由鍵接回、餘字 UTF-16 解碼（含三字詞）、非 BMP 鍵（𣘨 U+23628）
    let tai = corpus.suggestPhrases(after: "臺", limit: 30)
    checkEqual(tai.count, 30, "臺 has 30 phrases")
    checkEqual(Array(tai.prefix(4)), ["臺灣", "臺北市", "臺中", "臺南市"], "臺 phrases reconstructed with first char")
    checkEqual(corpus.suggestPhrases(after: "\u{23628}"), ["\u{23628}橠"], "non-BMP key phrase")
    check(corpus.suggestPhrases(after: "A").isEmpty, "unknown key → empty")
}

func testSuggestionEngineBasic() {
    let se = SuggestionEngine(prefs: MockPrefs())
    let s = se.suggest(recentCommitted: "日", lastText: "日")
    check(!s.isEmpty, "suggestions after 日")
    check(s.count <= 10, "at most 10 suggestions")
    let skip = se.suggest(recentCommitted: "的", lastText: "的")
    check(skip.isEmpty, "skip char 的 yields no word suggestions")
}

func testEngineSuggestFlow() {
    let (engine, mock) = makeEngine()
    engine.handleLetter("a")   // 日
    engine.handleSpace()
    checkEqual(mock.commits.last, "日", "committed 日")
    check(!mock.suggestions.isEmpty, "engineDidSuggest fired after commit")
    check(mock.suggestions.last?.isEmpty == false, "suggestions non-empty")
}

func testSuggestDisabled() {
    var prefs = MockPrefs()
    prefs.suggestEnabled = false
    let (engine, mock) = makeEngine(prefs: prefs)
    engine.handleLetter("a")
    engine.handleSpace()
    check(mock.suggestions.isEmpty, "no suggestions when disabled")
}

// === 常用語自訂組字碼 ===

func testUserPhrasesParseSerialize() {
    let text = "蝦米輸入法\n你好\txm\n  \n單\tq\n壞碼\tA B\n指令\t,,x\n"
    let entries = UserPhrases.parse(text)
    checkEqual(entries, [
        UserPhrases.Entry("蝦米輸入法"),
        UserPhrases.Entry("你好", "xm"),
        UserPhrases.Entry("單", "q"),
        UserPhrases.Entry("壞碼"),      // 不合法的碼丟掉、詞保留
        UserPhrases.Entry("指令"),      // ,, 前綴不能當碼
    ], "parse")
    checkEqual(UserPhrases.serialize(entries), "蝦米輸入法\n你好\txm\n單\tq\n壞碼\n指令\n", "serialize")
    checkEqual(UserPhrases.parse(UserPhrases.serialize(entries)), entries, "round trip")
}

func testUserPhrasesCodeValidation() {
    check(UserPhrases.isValidCode("abc"), "abc valid")
    check(UserPhrases.isValidCode("a,.'[]"), "punct valid")
    check(UserPhrases.isValidCode(",a"), ",a valid")
    check(!UserPhrases.isValidCode(""), "empty invalid")
    check(!UserPhrases.isValidCode(",,a"), ",, prefix invalid")
    check(!UserPhrases.isValidCode("Ab"), "uppercase invalid")
    check(!UserPhrases.isValidCode("a b"), "space invalid")
    check(!UserPhrases.isValidCode("a1"), "digit invalid")
}

func testShortcutTableLookup() {
    let table = makeFixtureTable()
    table.setShortcuts(["xm": ["蝦米輸入法"], "ab": ["明天見", "再見"], "abcdef": ["長碼"]])
    checkEqual(table.lookup("ab"), ["明"], "lookup 不含捷徑")
    checkEqual(table.shortcutLookup("ab"), ["明天見", "再見"], "shortcutLookup")
    checkEqual(table.shortcutLookup("XM"), ["蝦米輸入法"], "shortcutLookup case-insensitive")
    check(table.hasPrefix("x"), "捷徑前綴可續打")
    checkEqual(table.validNextKeys(after: "x"), Set(["m"]), "validNextKeys via shortcut")
    checkEqual(table.maxCodeLength, 6, "長捷徑拉高 maxCodeLength")
}

func testShortcutFreeCodeOnlyCandidate() {
    let (engine, mock) = makeEngine()
    engine.cinTable.setShortcuts(["xm": ["蝦米輸入法"]])
    engine.handleLetter("x")
    checkEqual(mock.candidateUpdates.last ?? ["?"], [], "x 無字表候選、只有捷徑前綴")
    engine.handleLetter("m")
    checkEqual(mock.candidateUpdates.last ?? [], ["蝦米輸入法"], "xm 只有捷徑詞")
    engine.handleSpace()
    checkEqual(mock.commits, ["蝦米輸入法"], "空白送出捷徑詞")
}

func testShortcutTakenCodeAfterExisting() {
    let (engine, mock) = makeEngine()
    engine.cinTable.setShortcuts(["ab": ["明天見"], "hj": ["再見"]])
    engine.handleLetter("a"); engine.handleLetter("b")
    checkEqual(mock.candidateUpdates.last ?? [], ["明", "明天見"], "撞碼排在字表候選後")
    engine.handleSpace()
    checkEqual(mock.commits, ["明"], "空白仍送出字表首選")
    engine.handleLetter("h"); engine.handleLetter("j")
    let cands = mock.candidateUpdates.last ?? []
    checkEqual(cands.count, 3, "hj 三個候選")
    checkEqual(cands.last ?? "", "再見", "捷徑排最後")
    engine.selectCandidate(at: 2)
    checkEqual(mock.commits, ["明", "再見"], "選捷徑詞上屏")
}

func testShortcutAutoCommit() {
    var prefs = MockPrefs(); prefs.autoCommit = true
    let (engine, mock) = makeEngine(prefs: prefs)
    engine.cinTable.setShortcuts(["xm": ["蝦米輸入法"]])
    engine.handleLetter("x"); engine.handleLetter("m")
    checkEqual(mock.commits, ["蝦米輸入法"], "唯一候選且無法續打 → 直接上屏")
}

// === Run ===

testHarness()
testCINCompileRoundtrip()
testCINCompileEncodings()
testEngineComposeAndCommit()
testEngineCommitComposingRaw()
testEngineEnglishPassthrough()
testEngineOverflowAutoCommit()
testEngineBackspaceAndEscape()
testEngineVRSF()
testEnginePunctuationPairing()
testEnginePairedRight()
testEngineCommaCommandUnknown()
testEngineModeSwitch()
testEngineSetEnglishMode()
testSkinSettingsParse()
testSkinSettingsParseFlat()
testWikiCorpusPhrases()
testZhuyinLookupBins()
testSuggestionEngineBasic()
testEngineSuggestFlow()
testUserPhrasesParseSerialize()
testUserPhrasesCodeValidation()
testShortcutTableLookup()
testShortcutFreeCodeOnlyCandidate()
testShortcutTakenCodeAfterExisting()
testShortcutAutoCommit()

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
