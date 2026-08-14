# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

OhMyBias 米 iOS — iOS 嘸蝦米（Boshiamy）鍵盤，**從 Yabomish 的 `YabomishIM/Sources/Shared/`（未發布的 iOS 實作）抽出**。純 Swift、零依賴。極簡版：保留**基本聯想詞**（萌典詞組 `phrases.bin`，CC0，687KB）＋使用者自訂詞，**不隨附**其他語料（詞級 n-gram、專業詞典、NER、emoji、地區用詞 — 上游 `WikiCorpus` 的這些 API 保留簽名、回傳空結果，`SuggestionEngine` 原始碼因此不需修改）。文件、commit、註解、UI 皆用繁體中文。

與家族的關係：`~/src/yabomish` = macOS 完整版（上游）；`~/src/ohmybias` = macOS 極簡版（**移除**聯想，桌面不需要）；本專案 = iOS 極簡版（**保留**基本聯想 — 手機上必要）。從上游移植修正時以 yabomish Shared/ 為準，不要參考 ohmybias 的 macOS 實體化。

## Build

Xcode 專案（iOS 需要 appex 打包簽章，無法如 macOS 版純 swiftc）：

```bash
xcodebuild -project OhMyBias.xcodeproj -scheme OhMyBias \
  -destination 'generic/platform=iOS Simulator' build   # 模擬器建置
open OhMyBias.xcodeproj                                  # 裝置部署：Xcode 設定 Team 後跑
```

兩個 target：**OhMyBias**（SwiftUI 容器 app — 匯入 liu.cin、偏好設定）、**OhMyBiasKeyboard**（鍵盤 appex）。專案用 Xcode 16 folder-synced group：`OhMyBiasApp/`、`OhMyBiasKeyboard/`、`Shared/`、`Resources/` 目錄即 target 內容，**加檔案＝放進目錄**，不用改 pbxproj。`Shared/` 與 `Resources/` 同時屬於兩個 target。

## Tests

```bash
Tests/run_tests.sh
```

Shared 引擎平台無關，測試在 **macOS host** 上以 swiftc 編譯執行（無 XCTest — `check`/`checkEqual` + `Tests/main.swift` 逐一呼叫）。`ClipboardProcessor`（UIKit）被 EXCLUDE regex 排除、以 `Tests/Stubs/` stub 取代 — 新增 UIKit 相關檔案到 Shared/ 時要同步加進 EXCLUDE。資料檔會被複製到測試 binary 旁（CLI 的 `Bundle.main` 即執行檔目錄）。`MockEngineDelegate` 記錄所有 delegate callback，是測引擎的標準做法。

## Architecture

- `Shared/`：**禁止 import UIKit**（唯一例外 `ClipboardProcessor.swift`）。`InputEngine.swift` 是核心狀態機（組字、選字、`,,` 指令、注音/拼音/同音查碼模式），透過 `InputEngineDelegate` 回呼；`IMEPreferences` 為可注入的偏好協定。`WikiCorpus` 在本專案是**極簡版**：只載 `phrases.bin`（PHMM mmap），其餘上游 API 回空。`FreqTracker` = freq.db SQLite 字頻學習＋`,,PIN` 固定排序（上游 iOS 側，含 iCloud merge）。
- `OhMyBiasKeyboard/`：`KeyboardViewController`（UIInputViewController）= `InputEngineDelegate` 的 iOS 實作；`KeyboardView` 字母/數字/符號/注音四頁；`CandidateBar` 候選列（聯想詞以藍字顯示，composing 為空時點選直接送出）。
- `OhMyBiasApp/`：SwiftUI 容器 — 匯入 liu.cin（`CINCompiler` 現場編成 liu.bin）、偏好 toggle、自訂詞編輯。
- 資料共享：App Group `group.info.plateaukao.ohmybias`（`AppConstants.sharedDir`）— liu.cin/liu.bin、freq.db、tables/、user_phrases.txt；偏好經 `UserDefaults(suiteName:)`（`OhMyBiasPrefs`）。
- Bundle IDs：app `info.plateaukao.ohmybias`、鍵盤 `info.plateaukao.ohmybias.keyboard`。

按鍵資料流：tap → `KeyboardViewController.handleKey` → `InputEngine`（`CINTable` mmap 查表、`CandidateRanker`＋`FreqTracker` 排序）→ delegate → CandidateBar／textDocumentProxy。commit 後 `SuggestionEngine` 產生聯想（user_phrases → 萌典詞組）。

## 注意事項

- **liu.cin 有版權（行易），只能使用者自行匯入、on-device 編譯，絕不預編/隨附 liu.bin。**
- `phrases.bin` 的 key 是詞首單字；萌典用「臺」不用「台」（打「台」不會出聯想，打「臺」才會）。
- 鍵盤 extension 記憶體上限約 60MB — `MemoryBudget` 管控 lazy 載入，新增資料結構要掛預算。
- `,,V` 剪貼簿指令需要鍵盤「完整取用權限」（RequestsOpenAccess 目前為 NO，未開時 toast 剪貼簿為空）。
