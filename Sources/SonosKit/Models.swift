import Foundation

struct SonosPlayer: Identifiable, Hashable {
    let id: String        // UDN from device description
    let name: String      // Room name
    let host: String      // IP address
    let port: Int         // typically 1400
}

struct PlaybackState {
    let transportState: String    // PLAYING, PAUSED_PLAYBACK, STOPPED
    let currentURI: String
    let currentURIMetadata: String
    let relTime: String           // HH:MM:SS
    let volume: Int
}

enum SonosError: LocalizedError {
    case soapFailed(action: String, statusCode: Int)
    case noLocalIP
    case ttsGenerationFailed

    var errorDescription: String? {
        switch self {
        case .soapFailed(let action, let statusCode):
            return "SOAP call '\(action)' failed with status \(statusCode)"
        case .noLocalIP:
            return "Could not determine local IP address"
        case .ttsGenerationFailed:
            return "Failed to generate text-to-speech audio"
        }
    }
}
