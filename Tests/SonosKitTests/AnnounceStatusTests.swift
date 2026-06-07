import XCTest
@testable import SonosKit

final class AnnounceStatusTests: XCTestCase {
    private let a = SonosPlayer(id: "A", name: "Kitchen", host: "h", port: 1400)
    private let b = SonosPlayer(id: "B", name: "Bedroom", host: "h", port: 1400)

    func testAllSucceeded() {
        let r = AnnounceResult(succeeded: [a, b], failed: [])
        XCTAssertEqual(announceStatusMessage(r), "Done!")
    }

    func testAllFailed() {
        let r = AnnounceResult(succeeded: [], failed: [FailedAnnounce(player: a, reason: "boom")])
        XCTAssertEqual(announceStatusMessage(r), "Failed: boom")
    }

    func testAllFailedWithNoReason() {
        let r = AnnounceResult(succeeded: [], failed: [])
        XCTAssertEqual(announceStatusMessage(r), "Failed: unknown error")
    }

    func testPartial() {
        let r = AnnounceResult(succeeded: [a], failed: [FailedAnnounce(player: b, reason: "x")])
        XCTAssertEqual(announceStatusMessage(r), "Announced to 1 of 2 — Bedroom failed")
    }
}
