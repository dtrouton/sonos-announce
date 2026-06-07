import Foundation

/// Parse the XML returned by the ZoneGroupTopology `GetZoneGroupState` action
/// into `SonosGroup` values. Uses XMLParser for robustness against attribute order.
public func parseZoneGroupState(_ xml: String) -> [SonosGroup] {
    let delegate = ZoneGroupParserDelegate()
    let parser = XMLParser(data: Data(xml.utf8))
    parser.delegate = delegate
    parser.parse()
    return delegate.groups
}

private final class ZoneGroupParserDelegate: NSObject, XMLParserDelegate {
    var groups: [SonosGroup] = []
    private var currentCoordinator: String?
    private var currentMembers: [(uuid: String, zone: String)] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        switch elementName {
        case "ZoneGroup":
            currentCoordinator = attributeDict["Coordinator"]
            currentMembers = []
        case "ZoneGroupMember":
            if let uuid = attributeDict["UUID"] {
                currentMembers.append((uuid, attributeDict["ZoneName"] ?? uuid))
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "ZoneGroup", let coordinator = currentCoordinator else { return }
        let coordName = currentMembers.first { $0.uuid == coordinator }?.zone
            ?? currentMembers.first?.zone
            ?? coordinator
        groups.append(SonosGroup(
            id: coordinator,
            name: coordName,
            coordinatorID: coordinator,
            memberIDs: currentMembers.map(\.uuid)
        ))
        currentCoordinator = nil
        currentMembers = []
    }
}

/// Fetches zone group topology from a reachable player via UPnP SOAP.
public struct SonosTopology {
    public init() {}

    /// Queries `GetZoneGroupState` on `player` and returns parsed groups.
    public func fetchGroups(from player: SonosPlayer) async throws -> [SonosGroup] {
        let url = URL(string: "http://\(player.host):\(player.port)/ZoneGroupTopology/Control")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "\"urn:schemas-upnp-org:service:ZoneGroupTopology:1#GetZoneGroupState\"",
            forHTTPHeaderField: "SOAPACTION"
        )
        request.httpBody = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" \
        s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body><u:GetZoneGroupState xmlns:u="urn:schemas-upnp-org:service:ZoneGroupTopology:1">\
        </u:GetZoneGroupState></s:Body></s:Envelope>
        """.utf8)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SonosError.soapFailed(action: "GetZoneGroupState",
                                        statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        // The state XML is itself entity-encoded inside the SOAP response.
        let body = String(data: data, encoding: .utf8) ?? ""
        let inner = extractXMLValue(from: body, tag: "ZoneGroupState").map(xmlUnescape) ?? body
        return parseZoneGroupState(inner)
    }
}
