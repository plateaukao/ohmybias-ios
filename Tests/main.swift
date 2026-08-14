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
testEngineBackspaceAndEscape()
testEngineVRSF()
testEnginePunctuationPairing()
testEngineCommaCommandUnknown()
testEngineModeSwitch()
testWikiCorpusPhrases()
testSuggestionEngineBasic()
testEngineSuggestFlow()
testSuggestDisabled()

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
