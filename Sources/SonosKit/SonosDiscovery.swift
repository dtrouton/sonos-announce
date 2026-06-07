import Foundation
import Network

@MainActor
public final class SonosDiscovery: ObservableObject {
    @Published public var players: [SonosPlayer] = []
    @Published public var isSearching = false

    private var browser: NWBrowser?

    public init() {}

    public func discover() async {
        isSearching = true

        // Step 1: Browse for Sonos services via Bonjour
        let endpoints = await browseForSonos()

        // Step 2: Resolve each endpoint to an IP address
        var resolvedHosts: [(host: String, port: Int)] = []
        for endpoint in endpoints {
            if let host = await Self.resolveEndpoint(endpoint) {
                resolvedHosts.append((host, 1400))
            }
        }

        // Step 3: Fetch device descriptions for room names
        var newPlayers: [SonosPlayer] = []
        for (host, port) in resolvedHosts {
            if let player = await Self.fetchDeviceDescription(host: host, port: port) {
                if !newPlayers.contains(where: { $0.id == player.id }) {
                    newPlayers.append(player)
                }
            }
        }

        players = newPlayers.sorted { $0.name < $1.name }
        isSearching = false
    }

    // MARK: - Bonjour Browse

    private func browseForSonos() async -> [NWEndpoint] {
        await withCheckedContinuation { continuation in
            let browser = NWBrowser(
                for: .bonjour(type: "_sonos._tcp", domain: "local."),
                using: .tcp
            )
            self.browser = browser

            var latestResults: Set<NWBrowser.Result> = []

            browser.browseResultsChangedHandler = { results, _ in
                latestResults = results
            }

            browser.stateUpdateHandler = { _ in }

            browser.start(queue: .main)

            // Collect results for 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                browser.cancel()
                self.browser = nil
                continuation.resume(returning: latestResults.map(\.endpoint))
            }
        }
    }

    // MARK: - Resolve Bonjour endpoint to IP via NWConnection

    private nonisolated static func resolveEndpoint(
        _ endpoint: NWEndpoint,
        timeout: TimeInterval = 5
    ) async -> String? {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(to: endpoint, using: .tcp)
            var resumed = false

            connection.stateUpdateHandler = { state in
                if resumed { return }

                switch state {
                case .ready:
                    if let path = connection.currentPath,
                       case .hostPort(let host, _) = path.remoteEndpoint {
                        resumed = true
                        var h = "\(host)"
                        // Strip IPv6 scope ID (e.g. "%en0")
                        if let i = h.firstIndex(of: "%") { h = String(h[..<i]) }
                        continuation.resume(returning: h)
                    } else {
                        resumed = true
                        continuation.resume(returning: nil)
                    }
                    connection.cancel()
                case .failed:
                    resumed = true
                    continuation.resume(returning: nil)
                    connection.cancel()
                case .cancelled:
                    if !resumed {
                        resumed = true
                        continuation.resume(returning: nil)
                    }
                default:
                    break
                }
            }

            connection.start(queue: .global())

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if !resumed {
                    resumed = true
                    continuation.resume(returning: nil)
                    connection.cancel()
                }
            }
        }
    }

    // MARK: - Device Description

    private nonisolated static func fetchDeviceDescription(host: String, port: Int) async -> SonosPlayer? {
        let url = URL(string: "http://\(host):\(port)/xml/device_description.xml")!
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let xml = String(data: data, encoding: .utf8) ?? ""

            let rawName = extractXMLValue(from: xml, tag: "roomName")
                ?? extractXMLValue(from: xml, tag: "friendlyName")
                ?? host
            let roomName = xmlUnescape(rawName)
            let udn = normalizeUDN(extractXMLValue(from: xml, tag: "UDN") ?? host)

            return SonosPlayer(id: udn, name: roomName, host: host, port: port)
        } catch {
            return nil
        }
    }
}
