# Changelog

## [0.1.0] - 2026-08-14

### 新增
- 從 Yabomish `Sources/Shared/`（未發布 iOS 實作）抽出引擎，iOS 側 `#if os(iOS)` 實體化
- 鍵盤 extension：字母／數字／符號／注音四頁、候選列、聯想詞列、toast／字根提示
- 容器 app：匯入 liu.cin（on-device 編譯）、偏好設定、自訂詞編輯
- 基本聯想詞：萌典詞組（phrases.bin，CC0）＋ user_phrases.txt，`,,SG` 開關
- 字頻學習（freq.db）＋ `,,PIN` 固定排序、注音／拼音／同音查碼、`,,` 指令系統
- 引擎測試（macOS host swiftc 執行）
