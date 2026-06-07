import Foundation

/// Returns the local IPv4 address of the first active `en*` interface.
public func getLocalIPAddress() -> String? {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
    defer { freeifaddrs(ifaddr) }

    for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let addr = ptr.pointee
        guard addr.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

        let name = String(cString: addr.ifa_name)
        guard name.hasPrefix("en") else { continue }

        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(
            addr.ifa_addr,
            socklen_t(addr.ifa_addr.pointee.sa_len),
            &hostname,
            socklen_t(hostname.count),
            nil, 0, NI_NUMERICHOST
        ) == 0 else { continue }
        let ip = String(cString: hostname)
        if !ip.hasPrefix("169.254") {
            return ip
        }
    }
    return nil
}
