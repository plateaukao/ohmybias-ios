import Foundation
import CoreGraphics
import ObjectiveC

/// CoreText 會把畫過的 emoji 字形以 CGImage 存進它自己的 NSCache（每顆約 36–65KB、
/// 行程全域），只在收到記憶體警告時才清 — 鍵盤 extension 常常等不到警告就先被 jetsam
/// 殺掉（實測逛 emoji 面板每一屏 +2MB、關面板也不會退）。
///
/// 做法同 SwiftKey：swizzle `NSCache.setObject(_:forKey:)`，看到有人把 CGImage 放進
/// NSCache 就把那個 cache 記下來（弱參照），面板關閉／切分類／記憶體吃緊時主動清空。
/// 只用公開 API（ObjC runtime 換掉 NSCache 公開方法的實作）；CoreText 找不到快取只是
/// 重畫一次，沒有其他副作用。若日後 CoreText 不再用 NSCache，這裡自然變成 no-op。
enum CoreTextGlyphCache {
    private static let caches = NSHashTable<AnyObject>.weakObjects()
    private static let lock = NSLock()
    private static var installed = false

    /// 安裝 swizzle（只做一次；重複呼叫無效）
    static func install() {
        lock.lock(); defer { lock.unlock() }
        guard !installed else { return }
        installed = true
        swizzleSetObject()
        swizzleSetObjectCost()
    }

    /// 清空所有記錄到的 CoreText 字形快取
    static func drain() {
        lock.lock()
        let all = caches.allObjects
        lock.unlock()
        for c in all { (c as? NSCache<AnyObject, AnyObject>)?.removeAllObjects() }
        // 字形 bitmap 釋放後 malloc 仍會留著整頁不還 — 明確要它交回 OS
        malloc_zone_pressure_relief(nil, 0)
    }

    /// 記憶體達門檻才清 — 逛大分類、連續捲動時呼叫，避免單次面板 session 內就撞上限
    static func drainIfNeeded(aboveMB threshold: Int) {
        guard MemoryBudget.currentMB >= threshold else { return }
        drain()
    }

    private static func register(_ cache: AnyObject) {
        lock.lock(); defer { lock.unlock() }
        caches.add(cache)
    }

    private static func isCGImage(_ obj: AnyObject) -> Bool {
        CFGetTypeID(obj as CFTypeRef) == CGImage.typeID
    }

    private static func swizzleSetObject() {
        let sel = #selector(NSCache<AnyObject, AnyObject>.setObject(_:forKey:))
        guard let m = class_getInstanceMethod(NSCache<AnyObject, AnyObject>.self, sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, AnyObject) -> Void
        let original = unsafeBitCast(method_getImplementation(m), to: Fn.self)
        let block: @convention(block) (AnyObject, AnyObject, AnyObject) -> Void = { cache, obj, key in
            if isCGImage(obj) { register(cache) }
            original(cache, sel, obj, key)
        }
        method_setImplementation(m, imp_implementationWithBlock(block))
    }

    private static func swizzleSetObjectCost() {
        let sel = #selector(NSCache<AnyObject, AnyObject>.setObject(_:forKey:cost:))
        guard let m = class_getInstanceMethod(NSCache<AnyObject, AnyObject>.self, sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, Int) -> Void
        let original = unsafeBitCast(method_getImplementation(m), to: Fn.self)
        let block: @convention(block) (AnyObject, AnyObject, AnyObject, Int) -> Void = { cache, obj, key, cost in
            if isCGImage(obj) { register(cache) }
            original(cache, sel, obj, key, cost)
        }
        method_setImplementation(m, imp_implementationWithBlock(block))
    }
}
