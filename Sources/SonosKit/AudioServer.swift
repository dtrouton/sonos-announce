import Foundation
import Network

/// Minimal HTTP server that serves a single audio file to Sonos speakers on the LAN.
class AudioServer {
    private var listener: NWListener?
    private var audioData: Data?
    private(set) var port: UInt16 = 0

    func start(data: Data) async throws {
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

    func stop() {
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

            // Parse Range header if present
            var rangeStart = 0
            var rangeEnd = audioData.count - 1
            var isRange = false

            for line in requestStr.split(separator: "\r\n") {
                if line.lowercased().hasPrefix("range:") {
                    let value = line.dropFirst("range:".count).trimmingCharacters(in: .whitespaces)
                    if value.hasPrefix("bytes=") {
                        let parts = value.dropFirst("bytes=".count).split(separator: "-")
                        if let start = parts.first.flatMap({ Int($0) }) {
                            rangeStart = min(start, audioData.count - 1)
                            if parts.count > 1, let end = Int(parts[1]) {
                                rangeEnd = min(end, audioData.count - 1)
                            }
                            isRange = true
                        }
                    }
                    break
                }
            }

            let sliceLength = rangeEnd - rangeStart + 1
            let responseData: Data

            if isRange {
                let header = "HTTP/1.1 206 Partial Content\r\n" +
                    "Content-Type: audio/wav\r\n" +
                    "Content-Length: \(sliceLength)\r\n" +
                    "Content-Range: bytes \(rangeStart)-\(rangeEnd)/\(audioData.count)\r\n" +
                    "Accept-Ranges: bytes\r\n" +
                    "Connection: close\r\n\r\n"
                responseData = header.data(using: .utf8)! + audioData[rangeStart...rangeEnd]
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
