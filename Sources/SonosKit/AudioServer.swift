import Foundation
import Network

/// Parse an HTTP `Range: bytes=start-end` header from a raw request string.
/// Returns nil when no Range header is present. End is clamped to totalLength-1
/// and defaults to totalLength-1 for open-ended ranges.
public func parseRangeHeader(_ request: String, totalLength: Int) -> (start: Int, end: Int)? {
    for line in request.split(separator: "\r\n") {
        guard line.lowercased().hasPrefix("range:") else { continue }
        let value = line.dropFirst("range:".count).trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("bytes=") else { return nil }
        let parts = value.dropFirst("bytes=".count).split(separator: "-", omittingEmptySubsequences: false)
        guard let start = parts.first.flatMap({ Int($0) }) else { return nil }
        let clampedStart = min(start, totalLength - 1)
        var end = totalLength - 1
        if parts.count > 1, let parsedEnd = Int(parts[1]) {
            end = min(parsedEnd, totalLength - 1)
        }
        return (clampedStart, end)
    }
    return nil
}

/// Minimal HTTP server that serves a single audio file to Sonos speakers on the LAN.
public final class AudioServer {
    private var listener: NWListener?
    private var audioData: Data?
    public private(set) var port: UInt16 = 0

    public init() {}

    public func start(data: Data) async throws {
        self.audioData = data

        let params = NWParameters.tcp
        let newListener = try NWListener(using: params, on: .any)
        self.listener = newListener

        self.port = try await withCheckedThrowingContinuation { continuation in
            var resumed = false

            newListener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume(returning: newListener.port?.rawValue ?? 0)
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            newListener.start(queue: .global(qos: .userInitiated))
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        audioData = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self, let audioData = self.audioData else {
                connection.cancel()
                return
            }

            let requestStr = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let range = parseRangeHeader(requestStr, totalLength: audioData.count)
            let responseData: Data
            if let range {
                let sliceLength = range.end - range.start + 1
                let header = "HTTP/1.1 206 Partial Content\r\n" +
                    "Content-Type: audio/wav\r\n" +
                    "Content-Length: \(sliceLength)\r\n" +
                    "Content-Range: bytes \(range.start)-\(range.end)/\(audioData.count)\r\n" +
                    "Accept-Ranges: bytes\r\n" +
                    "Connection: close\r\n\r\n"
                responseData = header.data(using: .utf8)! + audioData[(audioData.startIndex + range.start)...(audioData.startIndex + range.end)]
            } else {
                let header = "HTTP/1.1 200 OK\r\n" +
                    "Content-Type: audio/wav\r\n" +
                    "Content-Length: \(audioData.count)\r\n" +
                    "Accept-Ranges: bytes\r\n" +
                    "Connection: close\r\n\r\n"
                responseData = header.data(using: .utf8)! + audioData
            }

            connection.send(content: responseData, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
