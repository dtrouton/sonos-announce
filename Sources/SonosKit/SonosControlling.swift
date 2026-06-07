import Foundation

class SonosController {

    // MARK: - High-level Operations

    func snapshot(player: SonosPlayer) async throws -> PlaybackState {
        async let transport = getTransportInfo(player: player)
        async let position = getPositionInfo(player: player)
        async let vol = getVolume(player: player)

        let t = try await transport
        let p = try await position
        let v = try await vol

        return PlaybackState(
            transportState: t,
            currentURI: p.uri,
            currentURIMetadata: p.metadata,
            relTime: p.relTime,
            volume: v
        )
    }

    func announce(player: SonosPlayer, audioURL: String, volume: Int) async throws {
        try await setVolume(player: player, volume: volume)
        try await setAVTransportURI(player: player, uri: audioURL, metadata: "")
        try await play(player: player)
    }

    func waitForCompletion(player: SonosPlayer, audioDuration: TimeInterval, timeout: TimeInterval = 30) async throws {
        // Wait for at least the audio duration + buffer for Sonos to fetch/decode/play
        let minWait = max(audioDuration + 2.5, 4.0)
        try await Task.sleep(nanoseconds: UInt64(minWait * 1_000_000_000))

        // Poll to confirm it's done
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            let state = try await getTransportInfo(player: player)
            if state == "STOPPED" || state == "NO_MEDIA_PRESENT" {
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    func restore(player: SonosPlayer, state: PlaybackState) async throws {
        try await setVolume(player: player, volume: state.volume)

        guard !state.currentURI.isEmpty else { return }

        try await setAVTransportURI(
            player: player,
            uri: state.currentURI,
            metadata: state.currentURIMetadata
        )

        if state.relTime != "0:00:00" && state.relTime != "NOT_IMPLEMENTED" {
            try await seek(player: player, position: state.relTime)
        }

        if state.transportState == "PLAYING" {
            try await play(player: player)
        }
    }

    // MARK: - UPnP SOAP Calls

    private func getTransportInfo(player: SonosPlayer) async throws -> String {
        let response = try await soapCall(
            player: player,
            path: "/MediaRenderer/AVTransport/Control",
            service: "AVTransport",
            action: "GetTransportInfo",
            args: [("InstanceID", "0")]
        )
        return extractXMLValue(from: response, tag: "CurrentTransportState") ?? "UNKNOWN"
    }

    private func getPositionInfo(player: SonosPlayer) async throws -> (uri: String, metadata: String, relTime: String) {
        let response = try await soapCall(
            player: player,
            path: "/MediaRenderer/AVTransport/Control",
            service: "AVTransport",
            action: "GetPositionInfo",
            args: [("InstanceID", "0")]
        )
        return (
            uri: extractXMLValue(from: response, tag: "TrackURI") ?? "",
            metadata: extractXMLValue(from: response, tag: "TrackMetaData") ?? "",
            relTime: extractXMLValue(from: response, tag: "RelTime") ?? "0:00:00"
        )
    }

    private func getVolume(player: SonosPlayer) async throws -> Int {
        let response = try await soapCall(
            player: player,
            path: "/MediaRenderer/RenderingControl/Control",
            service: "RenderingControl",
            action: "GetVolume",
            args: [("InstanceID", "0"), ("Channel", "Master")]
        )
        return Int(extractXMLValue(from: response, tag: "CurrentVolume") ?? "0") ?? 0
    }

    private func setVolume(player: SonosPlayer, volume: Int) async throws {
        _ = try await soapCall(
            player: player,
            path: "/MediaRenderer/RenderingControl/Control",
            service: "RenderingControl",
            action: "SetVolume",
            args: [("InstanceID", "0"), ("Channel", "Master"), ("DesiredVolume", "\(volume)")]
        )
    }

    private func setAVTransportURI(player: SonosPlayer, uri: String, metadata: String) async throws {
        _ = try await soapCall(
            player: player,
            path: "/MediaRenderer/AVTransport/Control",
            service: "AVTransport",
            action: "SetAVTransportURI",
            args: [
                ("InstanceID", "0"),
                ("CurrentURI", xmlEscape(uri)),
                ("CurrentURIMetaData", metadata),  // Already entity-encoded from extraction
            ]
        )
    }

    private func play(player: SonosPlayer) async throws {
        _ = try await soapCall(
            player: player,
            path: "/MediaRenderer/AVTransport/Control",
            service: "AVTransport",
            action: "Play",
            args: [("InstanceID", "0"), ("Speed", "1")]
        )
    }

    private func seek(player: SonosPlayer, position: String) async throws {
        _ = try await soapCall(
            player: player,
            path: "/MediaRenderer/AVTransport/Control",
            service: "AVTransport",
            action: "Seek",
            args: [("InstanceID", "0"), ("Unit", "REL_TIME"), ("Target", position)]
        )
    }

    // MARK: - SOAP Helpers

    private func soapCall(
        player: SonosPlayer,
        path: String,
        service: String,
        action: String,
        args: [(String, String)]
    ) async throws -> String {
        let url = URL(string: "http://\(player.host):\(player.port)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "\"urn:schemas-upnp-org:service:\(service):1#\(action)\"",
            forHTTPHeaderField: "SOAPACTION"
        )
        request.httpBody = soapEnvelope(service: service, action: action, args: args).data(using: .utf8)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        let body = String(data: data, encoding: .utf8) ?? ""

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SonosError.soapFailed(action: action, statusCode: code)
        }
        return body
    }

    private func soapEnvelope(service: String, action: String, args: [(String, String)]) -> String {
        let argsXML = args.map { "<\($0.0)>\($0.1)</\($0.0)>" }.joined()
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" \
        s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body>
        <u:\(action) xmlns:u="urn:schemas-upnp-org:service:\(service):1">\
        \(argsXML)\
        </u:\(action)>
        </s:Body>
        </s:Envelope>
        """
    }
}
