import XCTest
@testable import SonosKit

final class SettingsStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = "test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        return d
    }

    func testDefaultsWhenEmpty() {
        let store = SettingsStore(defaults: freshDefaults())
        XCTAssertEqual(store.lastVolume, 50)
        XCTAssertTrue(store.selectedPlayerIDs.isEmpty)
        XCTAssertFalse(store.quickPhrases.isEmpty) // seeded defaults
        XCTAssertTrue(store.prefixEnabled)
    }

    func testRoundTripsSelectionAndVolume() {
        let d = freshDefaults()
        var store = SettingsStore(defaults: d)
        store.selectedPlayerIDs = ["AAA", "BBB"]
        store.lastVolume = 70
        store.prefixEnabled = false

        let reloaded = SettingsStore(defaults: d)
        XCTAssertEqual(reloaded.selectedPlayerIDs, ["AAA", "BBB"])
        XCTAssertEqual(reloaded.lastVolume, 70)
        XCTAssertFalse(reloaded.prefixEnabled)
    }

    func testRoundTripsQuickPhrases() {
        let d = freshDefaults()
        var store = SettingsStore(defaults: d)
        store.quickPhrases = ["One", "Two"]
        XCTAssertEqual(SettingsStore(defaults: d).quickPhrases, ["One", "Two"])
    }
}
