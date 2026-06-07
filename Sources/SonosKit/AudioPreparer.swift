import Foundation

/// Produced audio ready to be fetched by speakers.
public struct PreparedAudio: Sendable {
    public let url: String
    public let duration: TimeInterval
    public init(url: String, duration: TimeInterval) {
        self.url = url
        self.duration = duration
    }
}

/// Turns text into a fetchable audio URL and tears down resources afterward.
public protocol AudioPreparing: Sendable {
    func prepare(text: String) async throws -> PreparedAudio
    func cleanup() async
}

/// Local implementation: TTS → in-memory WAV → ephemeral HTTP server on the LAN.
public actor LocalAudioPreparer: AudioPreparing {
    private var server: AudioServer?

    public init() {}

    public func prepare(text: String) async throws -> PreparedAudio {
        let data = try await TTSGenerator.generate(text: text)
        let duration = wavDuration(data: data)
        guard let ip = getLocalIPAddress() else { throw SonosError.noLocalIP }

        let server = AudioServer()
        try await server.start(data: data)
        self.server = server
        return PreparedAudio(url: "http://\(ip):\(server.port)/announce.wav", duration: duration)
    }

    public func cleanup() async {
        server?.stop()
        server = nil
    }
}
