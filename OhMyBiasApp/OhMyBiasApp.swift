import SwiftUI

@main
struct OhMyBiasApp: App {
    init() {
        // 建立 App Group 共享資料夾結構
        let fm = FileManager.default
        try? fm.createDirectory(atPath: AppConstants.sharedDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: AppConstants.tablesDir, withIntermediateDirectories: true)
        // 首次啟動：語言模式歸零成嘸蝦米 — 偏好可能從備份還原／覆蓋安裝帶著舊的英文狀態
        if !OhMyBiasPrefs.firstLaunchDone {
            OhMyBiasPrefs.resetToChineseMode()
            OhMyBiasPrefs.firstLaunchDone = true
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
