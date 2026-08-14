import Foundation

/// Protocol to decouple Shared/ engine layer from concrete OhMyBiasPrefs.
/// Inject a test-double to unit-test engines without UserDefaults.
protocol IMEPreferences {
    var suggestEnabled: Bool { get }
    var autoCommit: Bool { get }
    var fuzzyMatch: Bool { get }
    var showCodeHint: Bool { get }
    var suggestStrategy: String { get }
    var wordCorpus: String { get }
    var charSuggest: Bool { get }
    var regionVariant: String { get }
    func domainEnabled(_ key: String) -> Bool
    func domainPriority(_ key: String) -> Int
    var punctuationPairing: Bool { get }
}

/// Bridges the static OhMyBiasPrefs into an instance conforming to IMEPreferences.
final class DefaultPreferences: IMEPreferences {
    static let shared = DefaultPreferences()
    var suggestEnabled: Bool { OhMyBiasPrefs.suggestEnabled }
    var autoCommit: Bool { OhMyBiasPrefs.autoCommit }
    var fuzzyMatch: Bool { OhMyBiasPrefs.fuzzyMatch }
    var showCodeHint: Bool { OhMyBiasPrefs.showCodeHint }
    var suggestStrategy: String { OhMyBiasPrefs.suggestStrategy }
    var wordCorpus: String { OhMyBiasPrefs.wordCorpus }
    var charSuggest: Bool { OhMyBiasPrefs.charSuggest }
    var regionVariant: String { OhMyBiasPrefs.regionVariant }
    func domainEnabled(_ key: String) -> Bool { OhMyBiasPrefs.domainEnabled(key) }
    func domainPriority(_ key: String) -> Int { OhMyBiasPrefs.domainPriority(key) }
    var punctuationPairing: Bool { OhMyBiasPrefs.punctuationPairing }
}
