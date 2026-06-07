import XCTest
@testable import SonosKit

final class AnnouncementServiceTests: XCTestCase {
    let kitchen = SonosPlayer(id: "AAA", name: "Kitchen", host: "10.0.0.2", port: 1400)
    let bedroom = SonosPlayer(id: "CCC", name: "Bedroom", host: "10.0.0.4", port: 1400)

    private func makeService(controller: MockSonosController, coords: [SonosPlayer],
                             preparer: StubAudioPreparer) -> LocalUPnPAnnouncementService {
        LocalUPnPAnnouncementService(
            controller: controller,
            resolver: StubCoordinatorResolver(coordinatorsToReturn: coords),
            audioPreparer: preparer
        )
    }

    func testAnnouncesToAllCoordinatorsAndReportsSuccess() async {
        let controller = MockSonosController()
        let preparer = StubAudioPreparer()
        let service = makeService(controller: controller, coords: [kitchen, bedroom], preparer: preparer)

        let result = await service.announce(message: "Dinner", to: [kitchen, bedroom], volume: 50)

        XCTAssertEqual(Set(result.succeeded.map(\.id)), ["AAA", "CCC"])
        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertEqual(Set(controller.announced), ["AAA", "CCC"])
    }

    func testRestoresEverySnapshottedCoordinator() async {
        let controller = MockSonosController()
        let preparer = StubAudioPreparer()
        let service = makeService(controller: controller, coords: [kitchen, bedroom], preparer: preparer)

        _ = await service.announce(message: "Dinner", to: [kitchen, bedroom], volume: 50)

        XCTAssertEqual(Set(controller.restored), ["AAA", "CCC"])
    }

    func testPartialFailureStillAnnouncesOthers() async {
        let controller = MockSonosController()
        controller.failAnnounceFor = ["CCC"]
        let preparer = StubAudioPreparer()
        let service = makeService(controller: controller, coords: [kitchen, bedroom], preparer: preparer)

        let result = await service.announce(message: "Dinner", to: [kitchen, bedroom], volume: 50)

        XCTAssertEqual(result.succeeded.map(\.id), ["AAA"])
        XCTAssertEqual(result.failed.map(\.player.id), ["CCC"])
    }

    func testAlwaysCleansUpAudio() async {
        let controller = MockSonosController()
        let preparer = StubAudioPreparer()
        let service = makeService(controller: controller, coords: [kitchen], preparer: preparer)

        _ = await service.announce(message: "Dinner", to: [kitchen], volume: 50)

        let cleaned = preparer.cleanedUp
        XCTAssertTrue(cleaned)
    }

    func testSnapshotFailureSkipsThatCoordinatorButContinues() async {
        let controller = MockSonosController()
        controller.failSnapshotFor = ["AAA"]
        let preparer = StubAudioPreparer()
        let service = makeService(controller: controller, coords: [kitchen, bedroom], preparer: preparer)

        let result = await service.announce(message: "Dinner", to: [kitchen, bedroom], volume: 50)

        XCTAssertEqual(result.succeeded.map(\.id), ["CCC"])
        XCTAssertEqual(result.failed.map(\.player.id), ["AAA"])
        XCTAssertFalse(controller.announced.contains("AAA"))
    }
}
