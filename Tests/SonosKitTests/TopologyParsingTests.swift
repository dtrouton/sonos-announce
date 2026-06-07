import XCTest
@testable import SonosKit

final class TopologyParsingTests: XCTestCase {
    let xml = """
    <ZoneGroupState>
      <ZoneGroups>
        <ZoneGroup Coordinator="RINCON_AAA" ID="RINCON_AAA:1">
          <ZoneGroupMember UUID="RINCON_AAA" ZoneName="Kitchen" Location="http://10.0.0.2:1400/xml/device_description.xml"/>
          <ZoneGroupMember UUID="RINCON_BBB" ZoneName="Living Room" Location="http://10.0.0.3:1400/xml/device_description.xml"/>
        </ZoneGroup>
        <ZoneGroup Coordinator="RINCON_CCC" ID="RINCON_CCC:2">
          <ZoneGroupMember UUID="RINCON_CCC" ZoneName="Bedroom" Location="http://10.0.0.4:1400/xml/device_description.xml"/>
        </ZoneGroup>
      </ZoneGroups>
    </ZoneGroupState>
    """

    func testParsesTwoGroups() {
        let groups = parseZoneGroupState(xml)
        XCTAssertEqual(groups.count, 2)
    }

    func testCoordinatorAndMembers() {
        let groups = parseZoneGroupState(xml)
        let kitchen = groups.first { $0.coordinatorID == "RINCON_AAA" }
        XCTAssertNotNil(kitchen)
        XCTAssertEqual(kitchen?.name, "Kitchen")
        XCTAssertEqual(Set(kitchen?.memberIDs ?? []), ["RINCON_AAA", "RINCON_BBB"])
    }

    func testStandaloneGroup() {
        let groups = parseZoneGroupState(xml)
        let bedroom = groups.first { $0.coordinatorID == "RINCON_CCC" }
        XCTAssertEqual(bedroom?.memberIDs, ["RINCON_CCC"])
    }

    func testEmptyXMLReturnsEmpty() {
        XCTAssertTrue(parseZoneGroupState("<garbage/>").isEmpty)
    }
}
