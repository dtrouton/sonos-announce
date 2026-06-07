import Foundation

public protocol AnnouncementService: Sendable {
    func announce(message: String, to players: [SonosPlayer], volume: Int) async -> AnnounceResult
}

/// Orchestrates a local-network announcement: resolve coordinators, prepare
/// audio, snapshot, play concurrently, wait, then restore. Each coordinator is
/// isolated so one failure does not abort the others; restore is best-effort and
/// guaranteed for every coordinator that was successfully snapshotted.
public final class LocalUPnPAnnouncementService: AnnouncementService {
    private let controller: SonosControlling
    private let resolver: CoordinatorResolving
    private let audioPreparer: AudioPreparing

    public init(controller: SonosControlling, resolver: CoordinatorResolving, audioPreparer: AudioPreparing) {
        self.controller = controller
        self.resolver = resolver
        self.audioPreparer = audioPreparer
    }

    public func announce(message: String, to players: [SonosPlayer], volume: Int) async -> AnnounceResult {
        var failed: [FailedAnnounce] = []

        let coordinators: [SonosPlayer]
        do {
            coordinators = try await resolver.coordinators(for: players)
        } catch {
            return AnnounceResult(succeeded: [], failed: players.map {
                FailedAnnounce(player: $0, reason: error.localizedDescription)
            })
        }
        guard !coordinators.isEmpty else { return AnnounceResult(succeeded: [], failed: []) }

        let audio: PreparedAudio
        do {
            audio = try await audioPreparer.prepare(text: message)
        } catch {
            return AnnounceResult(succeeded: [], failed: coordinators.map {
                FailedAnnounce(player: $0, reason: error.localizedDescription)
            })
        }

        // Snapshot — drop coordinators that fail to snapshot.
        var snapshots: [(SonosPlayer, PlaybackState)] = []
        for coord in coordinators {
            do {
                snapshots.append((coord, try await controller.snapshot(player: coord)))
            } catch {
                failed.append(FailedAnnounce(player: coord, reason: error.localizedDescription))
            }
        }

        // Announce concurrently; collect per-coordinator results.
        var succeeded: [SonosPlayer] = []
        await withTaskGroup(of: (SonosPlayer, String?).self) { group in
            for (coord, _) in snapshots {
                group.addTask { [controller, audio, volume] in
                    do {
                        try await controller.announce(player: coord, audioURL: audio.url, volume: volume)
                        return (coord, nil)
                    } catch {
                        return (coord, error.localizedDescription)
                    }
                }
            }
            for await (coord, err) in group {
                if let err {
                    failed.append(FailedAnnounce(player: coord, reason: err))
                } else {
                    succeeded.append(coord)
                }
            }
        }

        // Wait for one playing coordinator to finish (best effort).
        if let first = succeeded.first {
            try? await controller.waitForCompletion(player: first, audioDuration: audio.duration, timeout: 30)
        }

        // Guaranteed best-effort restore for every snapshotted coordinator.
        for (coord, state) in snapshots {
            try? await controller.restore(player: coord, state: state)
        }

        // Always clean up audio resources (best-effort, guaranteed).
        await audioPreparer.cleanup()

        return AnnounceResult(succeeded: succeeded, failed: failed)
    }
}
