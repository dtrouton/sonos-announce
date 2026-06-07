# SonosKit Foundation + macOS Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract all Sonos logic into a testable `SonosKit` Swift package, add grouped-speaker support, fix the audio-duration bug, add persisted settings, build a partial-success `AnnouncementService`, and refactor the existing macOS app onto it.

**Architecture:** A SwiftPM library target (`SonosKit`) holds all platform-agnostic logic behind protocols (`SonosControlling`, `CoordinatorResolving`, `AudioPreparing`, `AnnouncementService`) so orchestration is unit-testable with mocks and no real speakers. The macOS app becomes a thin executable target depending on `SonosKit`. A future iOS app (Plan 2) consumes the same library.

**Tech Stack:** Swift 5.9, SwiftPM, Foundation, Network, AVFoundation, XCTest. macOS 13+ / iOS 16+.

---

## File Structure

After this plan, the repo looks like:

```
sonos-announce/
├── Package.swift                       # SonosKit library + SonosKitTests + macOS executable
├── Sources/
│   └── SonosKit/
│       ├── Models.swift                # SonosPlayer, PlaybackState, SonosGroup, SonosError, AnnounceResult
│       ├── XMLUtilities.swift          # extractXMLValue, xmlEscape, xmlUnescape
│       ├── NetworkUtilities.swift      # getLocalIPAddress
│       ├── SonosDiscovery.swift        # Bonjour discovery
│       ├── SonosControlling.swift      # protocol + SonosController (SOAP)
│       ├── SonosTopology.swift         # parseZoneGroupState + SonosTopology fetch
│       ├── CoordinatorResolver.swift   # CoordinatorResolving + LiveCoordinatorResolver
│       ├── TTSGenerator.swift          # AVSpeechSynthesizer TTS + wavDuration
│       ├── AudioServer.swift           # NWListener HTTP server + parseRangeHeader
│       ├── AudioPreparer.swift         # AudioPreparing + LocalAudioPreparer
│       ├── AnnouncementService.swift   # AnnouncementService + LocalUPnPAnnouncementService
│       └── SettingsStore.swift         # UserDefaults-backed settings
├── Tests/
│   └── SonosKitTests/
│       ├── XMLUtilitiesTests.swift
│       ├── TopologyParsingTests.swift
│       ├── RangeHeaderTests.swift
│       ├── WavDurationTests.swift
│       ├── SettingsStoreTests.swift
│       ├── AnnouncementServiceTests.swift
│       └── Mocks.swift                 # MockSonosController, stub resolver/preparer
└── apps/
    └── macOS/
        ├── SonosAnnounceApp.swift
        ├── ContentView.swift
        ├── FlowLayout.swift
        └── Info.plist
```

**Naming/interface contract (used consistently across all tasks):**

- `SonosPlayer { id: String, name: String, host: String, port: Int }`
- `PlaybackState { transportState, currentURI, currentURIMetadata, relTime, volume }`
- `SonosGroup { id: String, name: String, coordinatorID: String, memberIDs: [String] }`
- `enum SonosError`: `.soapFailed(action:statusCode:)`, `.noLocalIP`, `.ttsGenerationFailed`, `.discoveryFailed`, `.permissionDenied`
- `protocol SonosControlling`: `snapshot(player:)`, `announce(player:audioURL:volume:)`, `waitForCompletion(player:audioDuration:timeout:)`, `restore(player:state:)`
- `protocol CoordinatorResolving`: `coordinators(for: [SonosPlayer]) async throws -> [SonosPlayer]`
- `struct PreparedAudio { url: String, duration: TimeInterval }`
- `protocol AudioPreparing`: `prepare(text:) async throws -> PreparedAudio`, `cleanup()`
- `struct AnnounceResult { succeeded: [SonosPlayer], failed: [FailedAnnounce] }`, `struct FailedAnnounce { player: SonosPlayer, reason: String }`
- `protocol AnnouncementService`: `announce(message:to:volume:) async -> AnnounceResult`

---

## Task 1: Restructure into a SwiftPM library + app target

**Files:**
- Modify: `Package.swift`
- Move: `Sources/{SonosPlayer,SonosController,SonosDiscovery,TTSGenerator,AudioServer,Utilities}.swift` → `Sources/SonosKit/`
- Move: `Sources/{SonosAnnounceApp,ContentView,FlowLayout}.swift` + `Sources/Info.plist` → `apps/macOS/`
- Rename: `Sources/SonosKit/SonosPlayer.swift` → `Sources/SonosKit/Models.swift`; `Sources/SonosKit/Utilities.swift` → split later (Task 2/3)

- [ ] **Step 1: Create directories and move files with git**

```bash
mkdir -p Sources/SonosKit apps/macOS Tests/SonosKitTests
git mv Sources/SonosPlayer.swift Sources/SonosKit/Models.swift
git mv Sources/SonosController.swift Sources/SonosKit/SonosControlling.swift
git mv Sources/SonosDiscovery.swift Sources/SonosKit/SonosDiscovery.swift
git mv Sources/TTSGenerator.swift Sources/SonosKit/TTSGenerator.swift
git mv Sources/AudioServer.swift Sources/SonosKit/AudioServer.swift
git mv Sources/Utilities.swift Sources/SonosKit/XMLUtilities.swift
git mv Sources/SonosAnnounceApp.swift apps/macOS/SonosAnnounceApp.swift
git mv Sources/ContentView.swift apps/macOS/ContentView.swift
git mv Sources/FlowLayout.swift apps/macOS/FlowLayout.swift
git mv Sources/Info.plist apps/macOS/Info.plist
```

- [ ] **Step 2: Rewrite `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SonosAnnounce",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "SonosKit", targets: ["SonosKit"]),
    ],
    targets: [
        .target(
            name: "SonosKit",
            path: "Sources/SonosKit"
        ),
        .testTarget(
            name: "SonosKitTests",
            dependencies: ["SonosKit"],
            path: "Tests/SonosKitTests"
        ),
        // The macOS app (apps/macOS) is temporarily NOT a build target during the
        // SonosKit extraction (Tasks 2-12) so `swift test` stays green while the app
        // references not-yet-public types. Task 13 restores this executable target.
        // .executableTarget(
        //     name: "SonosAnnounce",
        //     dependencies: ["SonosKit"],
        //     path: "apps/macOS",
        //     exclude: ["Info.plist"]
        // ),
    ]
)
```

> **Plan correction (discovered during execution):** `swift test` builds *all*
> declared targets, so leaving the broken macOS executable in the manifest would
> block test runs throughout Tasks 2–12. The executable target is therefore
> commented out here and restored in Task 13. SwiftPM ignores `apps/macOS`
> entirely while it is not part of any target.

- [ ] **Step 3: Add a placeholder test so the test target compiles**

Create `Tests/SonosKitTests/XMLUtilitiesTests.swift`:

```swift
import XCTest
@testable import SonosKit

final class PackageSmokeTests: XCTestCase {
    func testPackageBuilds() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 4: Make the macOS app import SonosKit**

At the top of `apps/macOS/ContentView.swift`, add `import SonosKit` after `import SwiftUI`. (The macOS app is not a build target until Task 13, so this file is not compiled yet; the import is added now so Task 13 has less to change.)

- [ ] **Step 5: Build and test (both green)**

Run: `swift build 2>&1 | tail -10` then `swift test 2>&1 | tail -10`
Expected: Both succeed. Only `SonosKit` + `SonosKitTests` are built (the macOS executable target is commented out), and the placeholder test passes.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: split Sources into SonosKit library and macOS app target"
```

---

## Task 2: Public XML utilities with tests

**Files:**
- Modify: `Sources/SonosKit/XMLUtilities.swift`
- Test: `Tests/SonosKitTests/XMLUtilitiesTests.swift`

- [ ] **Step 1: Write the failing tests**

Replace `Tests/SonosKitTests/XMLUtilitiesTests.swift` with:

```swift
import XCTest
@testable import SonosKit

final class XMLUtilitiesTests: XCTestCase {
    func testExtractsValueBetweenTags() {
        XCTAssertEqual(extractXMLValue(from: "<roomName>Kitchen</roomName>", tag: "roomName"), "Kitchen")
    }

    func testReturnsNilForMissingTag() {
        XCTAssertNil(extractXMLValue(from: "<a>x</a>", tag: "b"))
    }

    func testReturnsNilForEmptyValue() {
        XCTAssertNil(extractXMLValue(from: "<a></a>", tag: "a"))
    }

    func testEscapeReplacesEntities() {
        XCTAssertEqual(xmlEscape("a & b < c > d \" e"), "a &amp; b &lt; c &gt; d &quot; e")
    }

    func testUnescapeReversesEntities() {
        XCTAssertEqual(xmlUnescape("a &amp; b &lt; c &gt; d &quot; e &apos; f"), "a & b < c > d \" e ' f")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter XMLUtilitiesTests 2>&1 | tail -20`
Expected: FAIL — `extractXMLValue` etc. are `internal` and `@testable import` reaches them, but if the functions are not yet declared at file scope in the new file location the compiler errors. (If they already compile and pass, that is fine — the functions were ported intact; proceed to Step 3 to confirm.)

- [ ] **Step 3: Confirm the functions exist (no behavior change needed)**

`Sources/SonosKit/XMLUtilities.swift` should contain exactly the three functions `extractXMLValue`, `xmlUnescape`, `xmlEscape` ported from the original `Utilities.swift`. The `getLocalIPAddress` function moves to a new file in Task 3 — remove it from this file now:

Delete the `getLocalIPAddress()` function (lines starting `func getLocalIPAddress()` through its closing brace) from `Sources/SonosKit/XMLUtilities.swift`. Leave the three XML functions.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter XMLUtilitiesTests 2>&1 | tail -20`
Expected: PASS (5 tests). Note: the package will still fail to *build the macOS target*; run `swift test` which builds only library + tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SonosKit/XMLUtilities.swift Tests/SonosKitTests/XMLUtilitiesTests.swift
git commit -m "test: cover XML utilities; move getLocalIPAddress out"
```

---

## Task 3: NetworkUtilities (getLocalIPAddress, made public)

**Files:**
- Create: `Sources/SonosKit/NetworkUtilities.swift`

- [ ] **Step 1: Create the file**

```swift
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
```

- [ ] **Step 2: Build the test target**

Run: `swift build --target SonosKit 2>&1 | tail -10`
Expected: PASS (library compiles with the relocated function).

- [ ] **Step 3: Commit**

```bash
git add Sources/SonosKit/NetworkUtilities.swift
git commit -m "refactor: move getLocalIPAddress to NetworkUtilities, make public"
```

---

## Task 4: Public models + new SonosGroup, AnnounceResult, error cases

**Files:**
- Modify: `Sources/SonosKit/Models.swift`

- [ ] **Step 1: Replace `Models.swift` with public types**

```swift
import Foundation

public struct SonosPlayer: Identifiable, Hashable, Sendable {
    public let id: String        // UDN from device description
    public let name: String      // Room name
    public let host: String      // IP address
    public let port: Int         // typically 1400

    public init(id: String, name: String, host: String, port: Int) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
    }
}

public struct PlaybackState: Sendable {
    public let transportState: String    // PLAYING, PAUSED_PLAYBACK, STOPPED
    public let currentURI: String
    public let currentURIMetadata: String
    public let relTime: String           // HH:MM:SS
    public let volume: Int

    public init(transportState: String, currentURI: String, currentURIMetadata: String, relTime: String, volume: Int) {
        self.transportState = transportState
        self.currentURI = currentURI
        self.currentURIMetadata = currentURIMetadata
        self.relTime = relTime
        self.volume = volume
    }
}

/// A Sonos zone group: one coordinator plus zero or more member players.
public struct SonosGroup: Identifiable, Hashable, Sendable {
    public let id: String            // coordinator UDN, unique per group
    public let name: String          // coordinator room name (display)
    public let coordinatorID: String // UDN of the coordinating player
    public let memberIDs: [String]   // UDNs of all members (incl. coordinator)

    public init(id: String, name: String, coordinatorID: String, memberIDs: [String]) {
        self.id = id
        self.name = name
        self.coordinatorID = coordinatorID
        self.memberIDs = memberIDs
    }
}

/// Outcome of an announce across multiple coordinators.
public struct AnnounceResult: Sendable {
    public let succeeded: [SonosPlayer]
    public let failed: [FailedAnnounce]

    public init(succeeded: [SonosPlayer], failed: [FailedAnnounce]) {
        self.succeeded = succeeded
        self.failed = failed
    }

    public var allSucceeded: Bool { failed.isEmpty }
}

public struct FailedAnnounce: Sendable {
    public let player: SonosPlayer
    public let reason: String

    public init(player: SonosPlayer, reason: String) {
        self.player = player
        self.reason = reason
    }
}

public enum SonosError: LocalizedError {
    case soapFailed(action: String, statusCode: Int)
    case noLocalIP
    case ttsGenerationFailed
    case discoveryFailed
    case permissionDenied

    public var errorDescription: String? {
        switch self {
        case .soapFailed(let action, let statusCode):
            return "SOAP call '\(action)' failed with status \(statusCode)"
        case .noLocalIP:
            return "Could not determine local IP address"
        case .ttsGenerationFailed:
            return "Failed to generate text-to-speech audio"
        case .discoveryFailed:
            return "Could not reach any Sonos speaker"
        case .permissionDenied:
            return "Local network access is required to find your speakers"
        }
    }
}
```

- [ ] **Step 2: Build the library**

Run: `swift build --target SonosKit 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/SonosKit/Models.swift
git commit -m "feat: public models, add SonosGroup/AnnounceResult/error cases"
```

---

## Task 5: SonosControlling protocol + public SonosController

**Files:**
- Modify: `Sources/SonosKit/SonosControlling.swift` (was `SonosController.swift`)

- [ ] **Step 1: Add the protocol above the class**

At the top of `Sources/SonosKit/SonosControlling.swift`, after `import Foundation`, insert:

```swift
/// Abstraction over a single player's UPnP transport so orchestration can be
/// unit-tested against a mock without real speakers.
public protocol SonosControlling: Sendable {
    func snapshot(player: SonosPlayer) async throws -> PlaybackState
    func announce(player: SonosPlayer, audioURL: String, volume: Int) async throws
    func waitForCompletion(player: SonosPlayer, audioDuration: TimeInterval, timeout: TimeInterval) async throws
    func restore(player: SonosPlayer, state: PlaybackState) async throws
}
```

- [ ] **Step 2: Make `SonosController` conform and public**

Change the class declaration from `class SonosController {` to:

```swift
public final class SonosController: SonosControlling {
    public init() {}
```

Mark these four methods `public` (they already exist): `snapshot`, `announce`, `waitForCompletion`, `restore`. Add a default value note: the protocol requires `timeout` with no default, so change the existing signature `func waitForCompletion(player:audioDuration:timeout: TimeInterval = 30)` to keep the default in the class for app convenience — defaults are allowed on the concrete method even though the protocol declares the parameter.

So: `public func waitForCompletion(player: SonosPlayer, audioDuration: TimeInterval, timeout: TimeInterval = 30) async throws { ... }`

- [ ] **Step 3: Build the library**

Run: `swift build --target SonosKit 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/SonosKit/SonosControlling.swift
git commit -m "feat: add SonosControlling protocol, make SonosController public"
```

---

## Task 6: Zone group topology parsing (TDD)

**Files:**
- Create: `Sources/SonosKit/SonosTopology.swift`
- Test: `Tests/SonosKitTests/TopologyParsingTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SonosKitTests/TopologyParsingTests.swift`:

```swift
import XCTest
@testable import SonosKit

final class TopologyParsingTests: XCTestCase {
    // Minimal ZoneGroupState: one group of two (Kitchen coordinates, Living Room member),
    // one standalone group (Bedroom).
    let xml = """
    <ZoneGroupState>
      <ZoneGroups>
        <ZoneGroup Coordinator="RINCON_AAA" ID="RINCON_AAA:1">
          <ZoneGroupMember UUID="RINCON_AAA" ZoneName="Kitchen" Location="http://10.0.0.2:1400/xml/device_description.xml"/>
          <ZoneGroupMember UUID="RINCON_BBB" ZoneName="Living Room" Location="http://10.0.0.3:1400/xml/device_description.xml"/>
        </ZoneGroup>
        <ZoneGroup Coordinator="RINCON_CCC" ID="RINCON_CCC:2">
          <ZoneGroupMember UUID="RINCON_CCC" ZoneName="Bedroom" Location="http://10.0.0.4:1400/xml/device_description.xml"/>
        </ZoneGroup>
      </ZoneGroups>
    </ZoneGroupState>
    """

    func testParsesTwoGroups() {
        let groups = parseZoneGroupState(xml)
        XCTAssertEqual(groups.count, 2)
    }

    func testCoordinatorAndMembers() {
        let groups = parseZoneGroupState(xml)
        let kitchen = groups.first { $0.coordinatorID == "RINCON_AAA" }
        XCTAssertNotNil(kitchen)
        XCTAssertEqual(kitchen?.name, "Kitchen")
        XCTAssertEqual(Set(kitchen?.memberIDs ?? []), ["RINCON_AAA", "RINCON_BBB"])
    }

    func testStandaloneGroup() {
        let groups = parseZoneGroupState(xml)
        let bedroom = groups.first { $0.coordinatorID == "RINCON_CCC" }
        XCTAssertEqual(bedroom?.memberIDs, ["RINCON_CCC"])
    }

    func testEmptyXMLReturnsEmpty() {
        XCTAssertTrue(parseZoneGroupState("<garbage/>").isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter TopologyParsingTests 2>&1 | tail -20`
Expected: FAIL — "cannot find 'parseZoneGroupState' in scope".

- [ ] **Step 3: Implement `SonosTopology.swift`**

```swift
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter TopologyParsingTests 2>&1 | tail -20`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SonosKit/SonosTopology.swift Tests/SonosKitTests/TopologyParsingTests.swift
git commit -m "feat: parse ZoneGroupState into SonosGroup with tests"
```

---

## Task 7: CoordinatorResolving + LiveCoordinatorResolver (TDD)

**Files:**
- Create: `Sources/SonosKit/CoordinatorResolver.swift`
- Test: extend `Tests/SonosKitTests/TopologyParsingTests.swift` with resolver-mapping tests

- [ ] **Step 1: Write the failing test**

Append to `Tests/SonosKitTests/TopologyParsingTests.swift`:

```swift
final class CoordinatorMappingTests: XCTestCase {
    func testMapsMembersToDedupedCoordinators() {
        let kitchen = SonosPlayer(id: "RINCON_AAA", name: "Kitchen", host: "10.0.0.2", port: 1400)
        let living = SonosPlayer(id: "RINCON_BBB", name: "Living Room", host: "10.0.0.3", port: 1400)
        let bedroom = SonosPlayer(id: "RINCON_CCC", name: "Bedroom", host: "10.0.0.4", port: 1400)
        let groups = [
            SonosGroup(id: "RINCON_AAA", name: "Kitchen", coordinatorID: "RINCON_AAA",
                       memberIDs: ["RINCON_AAA", "RINCON_BBB"]),
            SonosGroup(id: "RINCON_CCC", name: "Bedroom", coordinatorID: "RINCON_CCC",
                       memberIDs: ["RINCON_CCC"]),
        ]
        // Selecting both members of the Kitchen group plus Bedroom should yield
        // two coordinators (Kitchen once, Bedroom once) — no duplicate Kitchen.
        let result = coordinators(for: [kitchen, living, bedroom],
                                  groups: groups,
                                  known: [kitchen, living, bedroom])
        XCTAssertEqual(Set(result.map(\.id)), ["RINCON_AAA", "RINCON_CCC"])
    }

    func testUngroupedPlayerMapsToItself() {
        let solo = SonosPlayer(id: "RINCON_ZZZ", name: "Office", host: "10.0.0.9", port: 1400)
        let result = coordinators(for: [solo], groups: [], known: [solo])
        XCTAssertEqual(result.map(\.id), ["RINCON_ZZZ"])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter CoordinatorMappingTests 2>&1 | tail -20`
Expected: FAIL — "cannot find 'coordinators(for:groups:known:)' in scope".

- [ ] **Step 3: Implement `CoordinatorResolver.swift`**

```swift
import Foundation

/// Resolves a set of selected players to the deduplicated set of group
/// coordinators that should actually receive commands.
public protocol CoordinatorResolving: Sendable {
    func coordinators(for players: [SonosPlayer]) async throws -> [SonosPlayer]
}

/// Pure mapping: for each selected player, find its group's coordinator and
/// return the deduped coordinator players. A player not present in any group is
/// treated as its own coordinator. `known` provides player objects for
/// coordinators that may not be in the selected set.
public func coordinators(
    for players: [SonosPlayer],
    groups: [SonosGroup],
    known: [SonosPlayer]
) -> [SonosPlayer] {
    let byID = Dictionary(known.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var coordinatorIDByMember: [String: String] = [:]
    for group in groups {
        for member in group.memberIDs {
            coordinatorIDByMember[member] = group.coordinatorID
        }
    }

    var seen = Set<String>()
    var result: [SonosPlayer] = []
    for player in players {
        let coordID = coordinatorIDByMember[player.id] ?? player.id
        guard !seen.contains(coordID) else { continue }
        seen.insert(coordID)
        if let coordPlayer = byID[coordID] ?? (coordID == player.id ? player : nil) {
            result.append(coordPlayer)
        }
    }
    return result
}

/// Live resolver: fetches topology from a reachable player, then maps.
public struct LiveCoordinatorResolver: CoordinatorResolving {
    private let known: [SonosPlayer]
    private let topology: SonosTopology

    public init(known: [SonosPlayer], topology: SonosTopology = SonosTopology()) {
        self.known = known
        self.topology = topology
    }

    public func coordinators(for players: [SonosPlayer]) async throws -> [SonosPlayer] {
        guard let probe = players.first ?? known.first else { return [] }
        let groups = (try? await topology.fetchGroups(from: probe)) ?? []
        return SonosKit.coordinators(for: players, groups: groups, known: known)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter CoordinatorMappingTests 2>&1 | tail -20`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SonosKit/CoordinatorResolver.swift Tests/SonosKitTests/TopologyParsingTests.swift
git commit -m "feat: coordinator resolution with dedup and tests"
```

---

## Task 8: WAV duration parsing (TDD) + TTS unification

**Files:**
- Modify: `Sources/SonosKit/TTSGenerator.swift`
- Test: `Tests/SonosKitTests/WavDurationTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SonosKitTests/WavDurationTests.swift`:

```swift
import XCTest
@testable import SonosKit

final class WavDurationTests: XCTestCase {
    /// Build a canonical 44-byte PCM WAV header for the given params plus
    /// `dataBytes` of silence, then assert the parsed duration.
    private func makeWAV(sampleRate: UInt32, channels: UInt16, bits: UInt16, dataBytes: Int) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(Data("RIFF".utf8)); u32(UInt32(36 + dataBytes)); d.append(Data("WAVE".utf8))
        d.append(Data("fmt ".utf8)); u32(16); u16(1); u16(channels); u32(sampleRate)
        let byteRate = sampleRate * UInt32(channels) * UInt32(bits / 8)
        u32(byteRate); u16(channels * bits / 8); u16(bits)
        d.append(Data("data".utf8)); u32(UInt32(dataBytes))
        d.append(Data(repeating: 0, count: dataBytes))
        return d
    }

    func testMono44100() {
        // 44100 bytes of 16-bit mono = 22050 frames = 0.5s
        let wav = makeWAV(sampleRate: 44100, channels: 1, bits: 16, dataBytes: 44100)
        XCTAssertEqual(wavDuration(data: wav), 0.5, accuracy: 0.001)
    }

    func testStereo22050() {
        // 22050 Hz, stereo, 16-bit, 1 second = 22050 * 2ch * 2bytes = 88200 bytes
        let wav = makeWAV(sampleRate: 22050, channels: 2, bits: 16, dataBytes: 88200)
        XCTAssertEqual(wavDuration(data: wav), 1.0, accuracy: 0.001)
    }

    func testTooShortReturnsZero() {
        XCTAssertEqual(wavDuration(data: Data([0x52, 0x49])), 0, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter WavDurationTests 2>&1 | tail -20`
Expected: FAIL — "cannot find 'wavDuration' in scope".

- [ ] **Step 3: Implement `wavDuration` and unify TTS**

Replace the entire contents of `Sources/SonosKit/TTSGenerator.swift` with:

```swift
import Foundation
import AVFoundation

/// Parse a canonical PCM WAV header and compute playback duration in seconds.
/// Reads sample rate, channel count, and bit depth from the header rather than
/// assuming 44.1kHz mono. Returns 0 for data too short to contain a header.
public func wavDuration(data: Data) -> TimeInterval {
    guard data.count >= 44 else { return 0 }
    func u16(_ off: Int) -> UInt16 {
        UInt16(data[data.startIndex + off]) | (UInt16(data[data.startIndex + off + 1]) << 8)
    }
    func u32(_ off: Int) -> UInt32 {
        UInt32(data[data.startIndex + off]) | (UInt32(data[data.startIndex + off + 1]) << 8)
            | (UInt32(data[data.startIndex + off + 2]) << 16) | (UInt32(data[data.startIndex + off + 3]) << 24)
    }
    let channels = max(1, Int(u16(22)))
    let sampleRate = max(1, Int(u32(24)))
    let bits = max(1, Int(u16(34)))
    let dataBytes = Int(u32(40))
    let bytesPerFrame = channels * (bits / 8)
    guard bytesPerFrame > 0 else { return 0 }
    return Double(dataBytes) / Double(sampleRate * bytesPerFrame)
}

public enum TTSGenerator {

    /// Generate 16-bit PCM WAV audio for `text` using AVSpeechSynthesizer on all
    /// platforms. Returns the WAV bytes.
    public static func generate(text: String) async throws -> Data {
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sonos_announce_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        return try await withCheckedThrowingContinuation { continuation in
            let synthesizer = AVSpeechSynthesizer()
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate

            var audioFile: AVAudioFile?
            var hasResumed = false

            synthesizer.write(utterance) { [synthesizer] buffer in
                _ = synthesizer // retain during synthesis
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }

                if pcm.frameLength == 0 {
                    guard !hasResumed else { return }
                    hasResumed = true
                    audioFile = nil // flush & close
                    do {
                        continuation.resume(returning: try Data(contentsOf: outputURL))
                    } catch {
                        continuation.resume(throwing: SonosError.ttsGenerationFailed)
                    }
                    return
                }

                do {
                    if audioFile == nil {
                        let settings: [String: Any] = [
                            AVFormatIDKey: Int(kAudioFormatLinearPCM),
                            AVSampleRateKey: pcm.format.sampleRate,
                            AVNumberOfChannelsKey: pcm.format.channelCount,
                            AVLinearPCMBitDepthKey: 16,
                            AVLinearPCMIsFloatKey: false,
                            AVLinearPCMIsBigEndianKey: false,
                        ]
                        audioFile = try AVAudioFile(forWriting: outputURL, settings: settings)
                    }
                    try audioFile?.write(from: pcm)
                } catch {
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(throwing: SonosError.ttsGenerationFailed)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter WavDurationTests 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SonosKit/TTSGenerator.swift Tests/SonosKitTests/WavDurationTests.swift
git commit -m "feat: unify TTS on AVSpeechSynthesizer; parse real WAV duration"
```

---

## Task 9: AudioServer Range parsing (TDD) + public API

**Files:**
- Modify: `Sources/SonosKit/AudioServer.swift`
- Test: `Tests/SonosKitTests/RangeHeaderTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SonosKitTests/RangeHeaderTests.swift`:

```swift
import XCTest
@testable import SonosKit

final class RangeHeaderTests: XCTestCase {
    func testNoRangeReturnsNil() {
        XCTAssertNil(parseRangeHeader("GET / HTTP/1.1\r\nHost: x\r\n\r\n", totalLength: 1000))
    }

    func testOpenEndedRange() {
        let r = parseRangeHeader("GET / HTTP/1.1\r\nRange: bytes=200-\r\n\r\n", totalLength: 1000)
        XCTAssertEqual(r?.start, 200)
        XCTAssertEqual(r?.end, 999)
    }

    func testClosedRange() {
        let r = parseRangeHeader("GET / HTTP/1.1\r\nRange: bytes=100-300\r\n\r\n", totalLength: 1000)
        XCTAssertEqual(r?.start, 100)
        XCTAssertEqual(r?.end, 300)
    }

    func testRangeClampedToLength() {
        let r = parseRangeHeader("Range: bytes=900-5000\r\n", totalLength: 1000)
        XCTAssertEqual(r?.start, 900)
        XCTAssertEqual(r?.end, 999)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter RangeHeaderTests 2>&1 | tail -20`
Expected: FAIL — "cannot find 'parseRangeHeader' in scope".

- [ ] **Step 3: Extract `parseRangeHeader` and use it in AudioServer**

Add this free function to `Sources/SonosKit/AudioServer.swift` (above the class):

```swift
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
```

Then change the class declaration to `public final class AudioServer {` with `public init() {}`, mark `start(data:)`, `stop()`, and `port` as `public`, and replace the inline Range-parsing block in `handleConnection` with a call to `parseRangeHeader`:

```swift
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter RangeHeaderTests 2>&1 | tail -20`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SonosKit/AudioServer.swift Tests/SonosKitTests/RangeHeaderTests.swift
git commit -m "feat: extract testable parseRangeHeader; make AudioServer public"
```

---

## Task 10: AudioPreparing + LocalAudioPreparer

**Files:**
- Create: `Sources/SonosKit/AudioPreparer.swift`

- [ ] **Step 1: Create the file**

```swift
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
```

- [ ] **Step 2: Build the library**

Run: `swift build --target SonosKit 2>&1 | tail -10`
Expected: PASS. (If `AudioServer.start` is not actor-safe to call cross-actor, this still compiles because `start` is `async`; resolve any Sendable warnings by leaving `AudioServer` a `final class` used only inside the actor.)

- [ ] **Step 3: Commit**

```bash
git add Sources/SonosKit/AudioPreparer.swift
git commit -m "feat: AudioPreparing protocol and LocalAudioPreparer"
```

---

## Task 11: AnnouncementService orchestration (TDD)

**Files:**
- Create: `Sources/SonosKit/AnnouncementService.swift`
- Create: `Tests/SonosKitTests/Mocks.swift`
- Test: `Tests/SonosKitTests/AnnouncementServiceTests.swift`

- [ ] **Step 1: Write the mocks**

Create `Tests/SonosKitTests/Mocks.swift`:

```swift
import Foundation
@testable import SonosKit

/// Records calls and can be told to fail for specific player IDs.
final class MockSonosController: SonosControlling, @unchecked Sendable {
    var failAnnounceFor: Set<String> = []
    var failSnapshotFor: Set<String> = []
    private(set) var announced: [String] = []
    private(set) var restored: [String] = []
    private(set) var snapshotted: [String] = []
    private let lock = NSLock()

    func snapshot(player: SonosPlayer) async throws -> PlaybackState {
        lock.lock(); snapshotted.append(player.id); lock.unlock()
        if failSnapshotFor.contains(player.id) { throw SonosError.soapFailed(action: "snapshot", statusCode: 500) }
        return PlaybackState(transportState: "PLAYING", currentURI: "x-uri:\(player.id)",
                             currentURIMetadata: "", relTime: "0:00:10", volume: 25)
    }

    func announce(player: SonosPlayer, audioURL: String, volume: Int) async throws {
        if failAnnounceFor.contains(player.id) { throw SonosError.soapFailed(action: "announce", statusCode: 500) }
        lock.lock(); announced.append(player.id); lock.unlock()
    }

    func waitForCompletion(player: SonosPlayer, audioDuration: TimeInterval, timeout: TimeInterval) async throws {}

    func restore(player: SonosPlayer, state: PlaybackState) async throws {
        lock.lock(); restored.append(player.id); lock.unlock()
    }
}

struct StubCoordinatorResolver: CoordinatorResolving {
    let coordinatorsToReturn: [SonosPlayer]
    func coordinators(for players: [SonosPlayer]) async throws -> [SonosPlayer] { coordinatorsToReturn }
}

final class StubAudioPreparer: AudioPreparing, @unchecked Sendable {
    private(set) var cleanedUp = false
    func prepare(text: String) async throws -> PreparedAudio {
        PreparedAudio(url: "http://10.0.0.1:8080/announce.wav", duration: 1.0)
    }
    func cleanup() async { cleanedUp = true }
}
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/SonosKitTests/AnnouncementServiceTests.swift`:

```swift
import XCTest
@testable import SonosKit

final class AnnouncementServiceTests: XCTestCase {
    let kitchen = SonosPlayer(id: "AAA", name: "Kitchen", host: "10.0.0.2", port: 1400)
    let bedroom = SonosPlayer(id: "CCC", name: "Bedroom", host: "10.0.0.4", port: 1400)

    private func makeService(controller: MockSonosController, coords: [SonosPlayer],
                             preparer: StubAudioPreparer) -> LocalUPnPAnnouncementService {
        LocalUPnPAnnouncementService(
            controller: controller,
            resolver: StubCoordinatorResolver(coordinatorsToReturn: coords),
            audioPreparer: preparer
        )
    }

    func testAnnouncesToAllCoordinatorsAndReportsSuccess() async {
        let controller = MockSonosController()
        let preparer = StubAudioPreparer()
        let service = makeService(controller: controller, coords: [kitchen, bedroom], preparer: preparer)

        let result = await service.announce(message: "Dinner", to: [kitchen, bedroom], volume: 50)

        XCTAssertEqual(Set(result.succeeded.map(\.id)), ["AAA", "CCC"])
        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertEqual(Set(controller.announced), ["AAA", "CCC"])
    }

    func testRestoresEverySnapshottedCoordinator() async {
        let controller = MockSonosController()
        let preparer = StubAudioPreparer()
        let service = makeService(controller: controller, coords: [kitchen, bedroom], preparer: preparer)

        _ = await service.announce(message: "Dinner", to: [kitchen, bedroom], volume: 50)

        XCTAssertEqual(Set(controller.restored), ["AAA", "CCC"])
    }

    func testPartialFailureStillAnnouncesOthers() async {
        let controller = MockSonosController()
        controller.failAnnounceFor = ["CCC"]
        let preparer = StubAudioPreparer()
        let service = makeService(controller: controller, coords: [kitchen, bedroom], preparer: preparer)

        let result = await service.announce(message: "Dinner", to: [kitchen, bedroom], volume: 50)

        XCTAssertEqual(result.succeeded.map(\.id), ["AAA"])
        XCTAssertEqual(result.failed.map(\.player.id), ["CCC"])
    }

    func testAlwaysCleansUpAudio() async {
        let controller = MockSonosController()
        let preparer = StubAudioPreparer()
        let service = makeService(controller: controller, coords: [kitchen], preparer: preparer)

        _ = await service.announce(message: "Dinner", to: [kitchen], volume: 50)

        let cleaned = preparer.cleanedUp
        XCTAssertTrue(cleaned)
    }

    func testSnapshotFailureSkipsThatCoordinatorButContinues() async {
        let controller = MockSonosController()
        controller.failSnapshotFor = ["AAA"]
        let preparer = StubAudioPreparer()
        let service = makeService(controller: controller, coords: [kitchen, bedroom], preparer: preparer)

        let result = await service.announce(message: "Dinner", to: [kitchen, bedroom], volume: 50)

        XCTAssertEqual(result.succeeded.map(\.id), ["CCC"])
        XCTAssertEqual(result.failed.map(\.player.id), ["AAA"])
        XCTAssertFalse(controller.announced.contains("AAA"))
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter AnnouncementServiceTests 2>&1 | tail -20`
Expected: FAIL — "cannot find 'LocalUPnPAnnouncementService' in scope".

- [ ] **Step 4: Implement `AnnouncementService.swift`**

```swift
import Foundation

public protocol AnnouncementService: Sendable {
    func announce(message: String, to players: [SonosPlayer], volume: Int) async -> AnnounceResult
}

/// Orchestrates a local-network announcement: resolve coordinators, prepare
/// audio, snapshot, play concurrently, wait, then restore. Each coordinator is
/// isolated so one failure does not abort the others; restore is best-effort and
/// guaranteed for every coordinator that was successfully snapshotted.
public final class LocalUPnPAnnouncementService: AnnouncementService {
    private let controller: SonosControlling
    private let resolver: CoordinatorResolving
    private let audioPreparer: AudioPreparing

    public init(controller: SonosControlling, resolver: CoordinatorResolving, audioPreparer: AudioPreparing) {
        self.controller = controller
        self.resolver = resolver
        self.audioPreparer = audioPreparer
    }

    public func announce(message: String, to players: [SonosPlayer], volume: Int) async -> AnnounceResult {
        var failed: [FailedAnnounce] = []

        let coordinators: [SonosPlayer]
        do {
            coordinators = try await resolver.coordinators(for: players)
        } catch {
            return AnnounceResult(succeeded: [], failed: players.map {
                FailedAnnounce(player: $0, reason: error.localizedDescription)
            })
        }
        guard !coordinators.isEmpty else { return AnnounceResult(succeeded: [], failed: []) }

        let audio: PreparedAudio
        do {
            audio = try await audioPreparer.prepare(text: message)
        } catch {
            return AnnounceResult(succeeded: [], failed: coordinators.map {
                FailedAnnounce(player: $0, reason: error.localizedDescription)
            })
        }
        defer { Task { await audioPreparer.cleanup() } }

        // Snapshot — drop coordinators that fail to snapshot.
        var snapshots: [(SonosPlayer, PlaybackState)] = []
        for coord in coordinators {
            do {
                snapshots.append((coord, try await controller.snapshot(player: coord)))
            } catch {
                failed.append(FailedAnnounce(player: coord, reason: error.localizedDescription))
            }
        }

        // Announce concurrently; collect per-coordinator results.
        var succeeded: [SonosPlayer] = []
        await withTaskGroup(of: (SonosPlayer, String?).self) { group in
            for (coord, _) in snapshots {
                group.addTask { [controller] in
                    do {
                        try await controller.announce(player: coord, audioURL: audio.url, volume: volume)
                        return (coord, nil)
                    } catch {
                        return (coord, error.localizedDescription)
                    }
                }
            }
            for await (coord, err) in group {
                if let err {
                    failed.append(FailedAnnounce(player: coord, reason: err))
                } else {
                    succeeded.append(coord)
                }
            }
        }

        // Wait for one playing coordinator to finish (best effort).
        if let first = succeeded.first {
            try? await controller.waitForCompletion(player: first, audioDuration: audio.duration, timeout: 30)
        }

        // Guaranteed best-effort restore for every snapshotted coordinator.
        for (coord, state) in snapshots {
            try? await controller.restore(player: coord, state: state)
        }

        return AnnounceResult(succeeded: succeeded, failed: failed)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter AnnouncementServiceTests 2>&1 | tail -20`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/SonosKit/AnnouncementService.swift Tests/SonosKitTests/Mocks.swift Tests/SonosKitTests/AnnouncementServiceTests.swift
git commit -m "feat: LocalUPnPAnnouncementService with partial-success and guaranteed restore"
```

---

## Task 12: SettingsStore (TDD)

**Files:**
- Create: `Sources/SonosKit/SettingsStore.swift`
- Test: `Tests/SonosKitTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SonosKitTests/SettingsStoreTests.swift`:

```swift
import XCTest
@testable import SonosKit

final class SettingsStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = "test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        return d
    }

    func testDefaultsWhenEmpty() {
        let store = SettingsStore(defaults: freshDefaults())
        XCTAssertEqual(store.lastVolume, 50)
        XCTAssertTrue(store.selectedPlayerIDs.isEmpty)
        XCTAssertFalse(store.quickPhrases.isEmpty) // seeded defaults
        XCTAssertTrue(store.prefixEnabled)
    }

    func testRoundTripsSelectionAndVolume() {
        let d = freshDefaults()
        var store = SettingsStore(defaults: d)
        store.selectedPlayerIDs = ["AAA", "BBB"]
        store.lastVolume = 70
        store.prefixEnabled = false

        let reloaded = SettingsStore(defaults: d)
        XCTAssertEqual(reloaded.selectedPlayerIDs, ["AAA", "BBB"])
        XCTAssertEqual(reloaded.lastVolume, 70)
        XCTAssertFalse(reloaded.prefixEnabled)
    }

    func testRoundTripsQuickPhrases() {
        let d = freshDefaults()
        var store = SettingsStore(defaults: d)
        store.quickPhrases = ["One", "Two"]
        XCTAssertEqual(SettingsStore(defaults: d).quickPhrases, ["One", "Two"])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter SettingsStoreTests 2>&1 | tail -20`
Expected: FAIL — "cannot find 'SettingsStore' in scope".

- [ ] **Step 3: Implement `SettingsStore.swift`**

```swift
import Foundation

/// UserDefaults-backed persistence for app settings. Value-type wrapper; each
/// property reads/writes through the injected defaults so it is testable with a
/// throwaway suite.
public struct SettingsStore {
    private let defaults: UserDefaults

    private enum Key {
        static let selected = "selectedPlayerIDs"
        static let volume = "lastVolume"
        static let phrases = "quickPhrases"
        static let prefixEnabled = "prefixEnabled"
        static let lastMessage = "lastMessage"
    }

    public static let defaultPhrases = [
        "Time to get ready for school!",
        "Dinner time!",
        "Come downstairs!",
        "Have a shower!",
    ]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var selectedPlayerIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.selected) ?? []) }
        nonmutating set { defaults.set(Array(newValue), forKey: Key.selected) }
    }

    public var lastVolume: Int {
        get { defaults.object(forKey: Key.volume) == nil ? 50 : defaults.integer(forKey: Key.volume) }
        nonmutating set { defaults.set(newValue, forKey: Key.volume) }
    }

    public var quickPhrases: [String] {
        get { defaults.stringArray(forKey: Key.phrases) ?? Self.defaultPhrases }
        nonmutating set { defaults.set(newValue, forKey: Key.phrases) }
    }

    public var prefixEnabled: Bool {
        get { defaults.object(forKey: Key.prefixEnabled) == nil ? true : defaults.bool(forKey: Key.prefixEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.prefixEnabled) }
    }

    public var lastMessage: String {
        get { defaults.string(forKey: Key.lastMessage) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: Key.lastMessage) }
    }
}
```

Note: properties are `nonmutating set` so a `let store` still persists — the test's `var store` also works.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter SettingsStoreTests 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the full suite**

Run: `swift test 2>&1 | tail -15`
Expected: All tests pass across XML, Topology, Coordinator, WavDuration, RangeHeader, AnnouncementService, SettingsStore.

- [ ] **Step 6: Commit**

```bash
git add Sources/SonosKit/SettingsStore.swift Tests/SonosKitTests/SettingsStoreTests.swift
git commit -m "feat: UserDefaults-backed SettingsStore with tests"
```

---

## Task 13: Refactor macOS app onto SonosKit

**Files:**
- Modify: `Package.swift` (restore the executable target)
- Modify: `apps/macOS/ContentView.swift`
- Modify: `apps/macOS/SonosAnnounceApp.swift` (only if it references moved types — it does not)

- [ ] **Step 0: Restore the macOS executable target in `Package.swift`**

Uncomment the `.executableTarget` block that Task 1 commented out, so the manifest again ends with:

```swift
        .executableTarget(
            name: "SonosAnnounce",
            dependencies: ["SonosKit"],
            path: "apps/macOS",
            exclude: ["Info.plist"]
        ),
    ]
)
```

- [ ] **Step 0b: Make `SonosDiscovery` public** (gap found during execution — the app module needs it)

In `Sources/SonosKit/SonosDiscovery.swift`: change `class SonosDiscovery` to `public final class SonosDiscovery`, add `public init() {}`, and mark `@Published public var players`, `@Published public var isSearching`, and `public func discover()` as public. Leave private members private. Run `swift build --target SonosKit` to confirm it still compiles.

- [ ] **Step 1: Update `ContentView` to use the service and store**

Replace the body of `apps/macOS/ContentView.swift`'s announce logic and state to consume SonosKit. Specifically:

1. Ensure `import SonosKit` is present.
2. Replace `private let controller = SonosController()` and the quick-phrase array with:

```swift
private let settings = SettingsStore()
@State private var quickPhrases: [String] = SettingsStore().quickPhrases
```

3. Initialize `volume` and `selectedPlayers` from settings in `.task`:

```swift
.task {
    selectedPlayers = settings.selectedPlayerIDs
    volume = Double(settings.lastVolume)
    await discovery.discover()
}
```

4. Persist on change — add after the volume `GroupBox`:

```swift
.onChange(of: selectedPlayers) { settings.selectedPlayerIDs = $0 }
.onChange(of: volume) { settings.lastVolume = Int($0) }
```

5. Replace the entire `announce()` function with a version that uses the service:

```swift
private func announce() async {
    let players = discovery.players.filter { selectedPlayers.contains($0.id) }
    guard !players.isEmpty else { return }

    isAnnouncing = true
    defer { isAnnouncing = false }

    settings.lastMessage = message
    let fullMessage = settings.prefixEnabled ? "Family announcement! \(message)" : message

    let service = LocalUPnPAnnouncementService(
        controller: SonosController(),
        resolver: LiveCoordinatorResolver(known: discovery.players),
        audioPreparer: LocalAudioPreparer()
    )

    status = "Announcing..."
    let result = await service.announce(message: fullMessage, to: players, volume: Int(volume))

    if result.allSucceeded {
        status = "Done!"
    } else if result.succeeded.isEmpty {
        status = "Failed: \(result.failed.first?.reason ?? "unknown error")"
    } else {
        let failedNames = result.failed.map(\.player.name).joined(separator: ", ")
        status = "Announced to \(result.succeeded.count) of \(result.succeeded.count + result.failed.count) — \(failedNames) failed"
    }

    try? await Task.sleep(nanoseconds: 3_000_000_000)
    status = ""
}
```

- [ ] **Step 2: Build the whole package (all targets)**

Run: `swift build 2>&1 | tail -20`
Expected: PASS — library, tests, and macOS executable all compile.

- [ ] **Step 3: Run the macOS app manually**

Run: `swift run SonosAnnounce`
Expected: Window opens, speakers discover, selecting + announcing plays on a real speaker and restores. Verify a grouped pair only triggers once. (This is the manual integration test; if no speakers are available, confirm the window renders and discovery runs without crashing.)

- [ ] **Step 4: Commit**

```bash
git add apps/macOS/ContentView.swift
git commit -m "refactor: macOS app uses SonosKit AnnouncementService + SettingsStore"
```

---

## Task 14: Update README and docs

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the architecture table and build instructions**

In `README.md`, update the architecture section to reflect the new layout: `SonosKit/` library modules and `apps/macOS/`. Replace the old per-file table rows that referenced `Sources/*.swift` with the SonosKit module table from this plan's File Structure section, and add: "Run `swift test` to run the SonosKit unit tests."

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: update README for SonosKit + apps layout"
```

---

## Self-Review

**Spec coverage** (each spec requirement → task):
- Shared `SonosKit` package, Approach A layout → Task 1
- Public models + `SonosGroup` → Task 4
- `SonosControlling` protocol → Task 5
- `SonosTopology` / grouping (`GetZoneGroupState`, coordinator targeting, dedup) → Tasks 6, 7, 11
- TTS unified on `AVSpeechSynthesizer` + real duration fix → Task 8
- `AudioServer` UUID filename + harden → Tasks 8 (UUID temp file), 9 (Range parsing)
- `AnnouncementService` protocol + concurrent play + partial success + guaranteed restore → Task 11
- `SettingsStore` (selected speakers, volume, phrases, prefix, last message) → Task 12
- Configurable announcement prefix (default on) → Task 12 (`prefixEnabled`) + Task 13 (applied)
- macOS app refactored onto shared core, still builds/runs → Task 13
- Testing strategy (pure logic + orchestration via mocks, `swift test`) → Tasks 2,6,7,8,9,11,12
- Editable quick phrases storage → Task 12 (`quickPhrases`); the editing *UI* is iOS Plan 2 / macOS already lists them

**Deferred to Plan 2 (iOS), intentionally not in this plan:** iOS Xcode project, SwiftUI revised-B UI, message-edit sheet, local-network permission UX, `beginBackgroundTask` handling, TestFlight. These require the Xcode app target and depend on the public interfaces finalized here.

**Placeholder scan:** No TBD/TODO; every code step shows complete code; every test step shows assertions and the run command with expected result.

**Type consistency:** `SonosControlling` (snapshot/announce/waitForCompletion/restore), `CoordinatorResolving.coordinators(for:)`, `AudioPreparing.prepare(text:)/cleanup()`, `PreparedAudio{url,duration}`, `AnnounceResult{succeeded,failed}`, `FailedAnnounce{player,reason}`, `SonosGroup{id,name,coordinatorID,memberIDs}` are used identically across Tasks 4–13.

**Known follow-ups (not blockers):** `LocalAudioPreparer` is an `actor`; `LocalUPnPAnnouncementService.announce`'s `defer { Task { await ... } }` cleanup is fire-and-forget — acceptable for the local server (process-bound). If Sendable warnings surface under strict concurrency, address them in the task where they appear without changing the public interface.
