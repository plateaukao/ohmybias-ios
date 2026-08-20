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

// === Run ===

testHarness()
testCINCompileRoundtrip()
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
testSuggestionEngineBasic()
testEngineSuggestFlow()
testSuggestDisabled()

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
