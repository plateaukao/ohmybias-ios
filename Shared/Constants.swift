import Foundation

enum AppConstants {
    static let appGroupID = "group.info.plateaukao.ohmybias"
    static let bundleIDApp = "info.plateaukao.ohmybias"
    static let bundleIDKeyboard = "info.plateaukao.ohmybias.keyboard"

    /// App Group 共享容器 — 主 app 與鍵盤 extension 共用（liu.cin/liu.bin、freq.db、tables/、user_phrases.txt）
    static var sharedDir: String {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?.path
            ?? NSHomeDirectory() + "/Documents"
    }

    static var cinPath: String { sharedDir + "/liu.cin" }
    static var freqPath: String { sharedDir + "/freq.db" }
    static var tablesDir: String { sharedDir + "/tables" }
}
