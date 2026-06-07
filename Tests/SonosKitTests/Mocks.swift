import Foundation
@testable import SonosKit

/// Records calls and can be told to fail for specific player IDs.
final class MockSonosController: SonosControlling, @unchecked Sendable {
    var failAnnounceFor: Set<String> = []
    var failSnapshotFor: Set<String> = []
    private(set) var announced: [String] = []
    private(set) var restored: [String] = []
    private(set) var snapshotted: [String] = []
    private let lock = NSLock()

    func snapshot(player: SonosPlayer) async throws -> PlaybackState {
        lock.lock(); snapshotted.append(player.id); lock.unlock()
        if failSnapshotFor.contains(player.id) { throw SonosError.soapFailed(action: "snapshot", statusCode: 500) }
        return PlaybackState(transportState: "PLAYING", currentURI: "x-uri:\(player.id)",
                             currentURIMetadata: "", relTime: "0:00:10", volume: 25)
    }

    func announce(player: SonosPlayer, audioURL: String, volume: Int) async throws {
        if failAnnounceFor.contains(player.id) { throw SonosError.soapFailed(action: "announce", statusCode: 500) }
        lock.lock(); announced.append(player.id); lock.unlock()
    }

    func waitForCompletion(player: SonosPlayer, audioDuration: TimeInterval, timeout: TimeInterval) async throws {}

    func restore(player: SonosPlayer, state: PlaybackState) async throws {
        lock.lock(); restored.append(player.id); lock.unlock()
    }
}

struct StubCoordinatorResolver: CoordinatorResolving {
    let coordinatorsToReturn: [SonosPlayer]
    func coordinators(for players: [SonosPlayer]) async throws -> [SonosPlayer] { coordinatorsToReturn }
}

final class StubAudioPreparer: AudioPreparing, @unchecked Sendable {
    private(set) var cleanedUp = false
    func prepare(text: String) async throws -> PreparedAudio {
        PreparedAudio(url: "http://10.0.0.1:8080/announce.wav", duration: 1.0)
    }
    func cleanup() async { cleanedUp = true }
}
