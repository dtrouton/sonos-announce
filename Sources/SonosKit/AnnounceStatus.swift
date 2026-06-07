import Foundation

/// Human-readable one-line status for an announce outcome, shared by both apps.
public func announceStatusMessage(_ result: AnnounceResult) -> String {
    if result.allSucceeded && !result.succeeded.isEmpty {
        return "Done!"
    }
    if result.succeeded.isEmpty {
        return "Failed: \(result.failed.first?.reason ?? "unknown error")"
    }
    let names = result.failed.map(\.player.name).joined(separator: ", ")
    let total = result.succeeded.count + result.failed.count
    return "Announced to \(result.succeeded.count) of \(total) — \(names) failed"
}
