import XCTest
@testable import SonosKit

final class GroupedPlayerIDsTests: XCTestCase {
    func testOnlyMultiMemberGroupsCount() {
        let groups = [
            SonosGroup(id: "A", name: "Kitchen", coordinatorID: "A", memberIDs: ["A", "B"]),
            SonosGroup(id: "C", name: "Bedroom", coordinatorID: "C", memberIDs: ["C"]),
        ]
        XCTAssertEqual(groupedPlayerIDs(from: groups), ["A", "B"])
    }

    func testNoGroupsIsEmpty() {
        XCTAssertTrue(groupedPlayerIDs(from: []).isEmpty)
    }
}
