import SwiftUI

@main
struct OhMyBiasApp: App {
    init() {
        // 建立 App Group 共享資料夾結構
        let fm = FileManager.default
        try? fm.createDirectory(atPath: AppConstants.sharedDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: AppConstants.tablesDir, withIntermediateDirectories: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
