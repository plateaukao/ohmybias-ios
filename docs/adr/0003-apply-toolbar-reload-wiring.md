# ADR 0003：接入工具列重載掛接

## 狀態

已採用。

## 背景

ADR 0002 已決定鍵盤出現時重建工具列，但此行為必須由
`KeyboardViewController` 呼叫 CandidateBar 並將鍵面頂端留白交給它。

## 決策

在 `viewWillAppear` 重載 SkinSettings、重建工具列並恢復中英模式圖示；將
`KeyboardView.yieldTopMargin` 改由 CandidateBar 的工具列／候選列可見狀態決定。

## 後果

使用者的工具列配置能在既有 extension 行程再次出現時生效，且工具列下緣觸控
不會被第一排鍵攔截。
