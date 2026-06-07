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
