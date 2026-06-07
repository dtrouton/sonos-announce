import Foundation

/// Extract the text content between XML tags using simple string matching.
/// Does NOT decode XML entities, so extracted text can be re-embedded in XML as-is.
func extractXMLValue(from xml: String, tag: String) -> String? {
    guard let startRange = xml.range(of: "<\(tag)>"),
          let endRange = xml.range(of: "</\(tag)>", range: startRange.upperBound..<xml.endIndex)
    else { return nil }
    let value = String(xml[startRange.upperBound..<endRange.lowerBound])
    return value.isEmpty ? nil : value
}

/// Decode standard XML entities for display purposes.
func xmlUnescape(_ string: String) -> String {
    string
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&apos;", with: "'")
}

func xmlEscape(_ string: String) -> String {
    string
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

/// Returns the local IPv4 address of the first active `en*` interface.
func getLocalIPAddress() -> String? {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
    defer { freeifaddrs(ifaddr) }

    for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let addr = ptr.pointee
        guard addr.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

        let name = String(cString: addr.ifa_name)
        guard name.hasPrefix("en") else { continue }

        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        getnameinfo(
            addr.ifa_addr,
            socklen_t(addr.ifa_addr.pointee.sa_len),
            &hostname,
            socklen_t(hostname.count),
            nil, 0, NI_NUMERICHOST
        )
        let ip = String(cString: hostname)
        if !ip.hasPrefix("169.254") {
            return ip
        }
    }
    return nil
}
