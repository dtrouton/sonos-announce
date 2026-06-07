import Foundation

/// Resolves a set of selected players to the deduplicated set of group
/// coordinators that should actually receive commands.
public protocol CoordinatorResolving: Sendable {
    func coordinators(for players: [SonosPlayer]) async throws -> [SonosPlayer]
}

/// Pure mapping: for each selected player, find its group's coordinator and
/// return the deduped coordinator players. A player not present in any group is
/// treated as its own coordinator. `known` provides player objects for
/// coordinators that may not be in the selected set.
public func coordinators(
    for players: [SonosPlayer],
    groups: [SonosGroup],
    known: [SonosPlayer]
) -> [SonosPlayer] {
    let byID = Dictionary(known.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var coordinatorIDByMember: [String: String] = [:]
    for group in groups {
        for member in group.memberIDs {
            coordinatorIDByMember[member] = group.coordinatorID
        }
    }

    var seen = Set<String>()
    var result: [SonosPlayer] = []
    for player in players {
        let coordID = coordinatorIDByMember[player.id] ?? player.id
        guard !seen.contains(coordID) else { continue }
        seen.insert(coordID)
        if let coordPlayer = byID[coordID] ?? (coordID == player.id ? player : nil) {
            result.append(coordPlayer)
        }
    }
    return result
}

/// Live resolver: fetches topology from a reachable player, then maps.
public struct LiveCoordinatorResolver: CoordinatorResolving {
    private let known: [SonosPlayer]
    private let topology: SonosTopology

    public init(known: [SonosPlayer], topology: SonosTopology = SonosTopology()) {
        self.known = known
        self.topology = topology
    }

    public func coordinators(for players: [SonosPlayer]) async throws -> [SonosPlayer] {
        guard let probe = players.first ?? known.first else { return [] }
        let groups = (try? await topology.fetchGroups(from: probe)) ?? []
        return SonosKit.coordinators(for: players, groups: groups, known: known)
    }
}
