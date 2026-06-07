import XCTest
@testable import SonosKit

final class RangeHeaderTests: XCTestCase {
    func testNoRangeReturnsNil() {
        XCTAssertNil(parseRangeHeader("GET / HTTP/1.1\r\nHost: x\r\n\r\n", totalLength: 1000))
    }

    func testOpenEndedRange() {
        let r = parseRangeHeader("GET / HTTP/1.1\r\nRange: bytes=200-\r\n\r\n", totalLength: 1000)
        XCTAssertEqual(r?.start, 200)
        XCTAssertEqual(r?.end, 999)
    }

    func testClosedRange() {
        let r = parseRangeHeader("GET / HTTP/1.1\r\nRange: bytes=100-300\r\n\r\n", totalLength: 1000)
        XCTAssertEqual(r?.start, 100)
        XCTAssertEqual(r?.end, 300)
    }

    func testRangeClampedToLength() {
        let r = parseRangeHeader("Range: bytes=900-5000\r\n", totalLength: 1000)
        XCTAssertEqual(r?.start, 900)
        XCTAssertEqual(r?.end, 999)
    }
}
