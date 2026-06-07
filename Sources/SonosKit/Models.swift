import Foundation

public struct SonosPlayer: Identifiable, Hashable, Sendable {
    public let id: String        // UDN from device description
    public let name: String      // Room name
    public let host: String      // IP address
    public let port: Int         // typically 1400

    public init(id: String, name: String, host: String, port: Int) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
    }
}

public struct PlaybackState: Sendable {
    public let transportState: String    // PLAYING, PAUSED_PLAYBACK, STOPPED
    public let currentURI: String
    public let currentURIMetadata: String
    public let relTime: String           // HH:MM:SS
    public let volume: Int

    public init(transportState: String, currentURI: String, currentURIMetadata: String, relTime: String, volume: Int) {
        self.transportState = transportState
        self.currentURI = currentURI
        self.currentURIMetadata = currentURIMetadata
        self.relTime = relTime
        self.volume = volume
    }
}

/// A Sonos zone group: one coordinator plus zero or more member players.
public struct SonosGroup: Identifiable, Hashable, Sendable {
    public let id: String            // coordinator UDN, unique per group
    public let name: String          // coordinator room name (display)
    public let coordinatorID: String // UDN of the coordinating player
    public let memberIDs: [String]   // UDNs of all members (incl. coordinator)

    public init(id: String, name: String, coordinatorID: String, memberIDs: [String]) {
        self.id = id
        self.name = name
        self.coordinatorID = coordinatorID
        self.memberIDs = memberIDs
    }
}

/// Outcome of an announce across multiple coordinators.
public struct AnnounceResult: Sendable {
    public let succeeded: [SonosPlayer]
    public let failed: [FailedAnnounce]

    public init(succeeded: [SonosPlayer], failed: [FailedAnnounce]) {
        self.succeeded = succeeded
        self.failed = failed
    }

    public var allSucceeded: Bool { failed.isEmpty }
}

public struct FailedAnnounce: Sendable {
    public let player: SonosPlayer
    public let reason: String

    public init(player: SonosPlayer, reason: String) {
        self.player = player
        self.reason = reason
    }
}

public enum SonosError: LocalizedError {
    case soapFailed(action: String, statusCode: Int)
    case noLocalIP
    case ttsGenerationFailed
    case discoveryFailed
    case permissionDenied

    public var errorDescription: String? {
        switch self {
        case .soapFailed(let action, let statusCode):
            return "SOAP call '\(action)' failed with status \(statusCode)"
        case .noLocalIP:
            return "Could not determine local IP address"
        case .ttsGenerationFailed:
            return "Failed to generate text-to-speech audio"
        case .discoveryFailed:
            return "Could not reach any Sonos speaker"
        case .permissionDenied:
            return "Local network access is required to find your speakers"
        }
    }
}
