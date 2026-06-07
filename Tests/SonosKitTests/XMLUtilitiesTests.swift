import XCTest
@testable import SonosKit

final class XMLUtilitiesTests: XCTestCase {
    func testExtractsValueBetweenTags() {
        XCTAssertEqual(extractXMLValue(from: "<roomName>Kitchen</roomName>", tag: "roomName"), "Kitchen")
    }

    func testReturnsNilForMissingTag() {
        XCTAssertNil(extractXMLValue(from: "<a>x</a>", tag: "b"))
    }

    func testReturnsNilForEmptyValue() {
        XCTAssertNil(extractXMLValue(from: "<a></a>", tag: "a"))
    }

    func testEscapeReplacesEntities() {
        XCTAssertEqual(xmlEscape("a & b < c > d \" e"), "a &amp; b &lt; c &gt; d &quot; e")
    }

    func testUnescapeReversesEntities() {
        XCTAssertEqual(xmlUnescape("a &amp; b &lt; c &gt; d &quot; e &apos; f"), "a & b < c > d \" e ' f")
    }
}
