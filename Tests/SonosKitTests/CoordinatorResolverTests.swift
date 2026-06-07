import XCTest
@testable import SonosKit

final class CoordinatorMappingTests: XCTestCase {
    func testMapsMembersToDedupedCoordinators() {
        let kitchen = SonosPlayer(id: "RINCON_AAA", name: "Kitchen", host: "10.0.0.2", port: 1400)
        let living = SonosPlayer(id: "RINCON_BBB", name: "Living Room", host: "10.0.0.3", port: 1400)
        let bedroom = SonosPlayer(id: "RINCON_CCC", name: "Bedroom", host: "10.0.0.4", port: 1400)
        let groups = [
            SonosGroup(id: "RINCON_AAA", name: "Kitchen", coordinatorID: "RINCON_AAA",
                       memberIDs: ["RINCON_AAA", "RINCON_BBB"]),
            SonosGroup(id: "RINCON_CCC", name: "Bedroom", coordinatorID: "RINCON_CCC",
                       memberIDs: ["RINCON_CCC"]),
        ]
        let result = coordinators(for: [kitchen, living, bedroom],
                                  groups: groups,
                                  known: [kitchen, living, bedroom])
        XCTAssertEqual(Set(result.map(\.id)), ["RINCON_AAA", "RINCON_CCC"])
    }

    func testUngroupedPlayerMapsToItself() {
        let solo = SonosPlayer(id: "RINCON_ZZZ", name: "Office", host: "10.0.0.9", port: 1400)
        let result = coordinators(for: [solo], groups: [], known: [solo])
        XCTAssertEqual(result.map(\.id), ["RINCON_ZZZ"])
    }
}
