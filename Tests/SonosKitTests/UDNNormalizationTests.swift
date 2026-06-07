import XCTest
@testable import SonosKit

final class UDNNormalizationTests: XCTestCase {
    func testStripsUuidPrefix() {
        XCTAssertEqual(normalizeUDN("uuid:RINCON_347E5C4BDD7201400"), "RINCON_347E5C4BDD7201400")
    }

    func testLeavesBareFormUnchanged() {
        XCTAssertEqual(normalizeUDN("RINCON_347E5C4BDD7201400"), "RINCON_347E5C4BDD7201400")
    }

    func testIsCaseInsensitiveOnPrefix() {
        XCTAssertEqual(normalizeUDN("UUID:RINCON_X"), "RINCON_X")
    }
}
