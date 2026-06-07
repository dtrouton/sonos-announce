# iPhone Sonos Announce — Stage 1 Design

**Date:** 2026-06-07
**Status:** Approved (pending implementation plan)

## Summary

Rewrite Sonos Announce as an iPhone-first app while keeping the existing macOS
app working. Both apps share a platform-agnostic Swift package (`SonosKit`)
that holds all the Sonos logic. Stage 1 uses the existing local UPnP / on-device
HTTP-server approach (no accounts, no backend). The architecture deliberately
leaves a protocol seam so a future Stage 2 can add the official Sonos cloud
`audioClip` API behind the same interface without touching the UI.

## Goals

- Ship an iPhone app distributable via **TestFlight** to family (not full App
  Store review, but real signed builds on real devices).
- Keep the macOS app building and usable, sharing one copy of the logic.
- Fix the biggest correctness gaps from the original app: grouped-speaker
  handling, iOS audio-duration estimation, and all-or-nothing error handling.
- Add quality-of-life features: persisted settings, editable quick phrases.

## Non-Goals (Stage 1)

- The Sonos cloud `audioClip` API, OAuth, and any backend (that is Stage 2).
- Remote (off-LAN) announcements — Stage 1 is home-Wi-Fi only.
- Reliable background operation — Stage 1 expects the app to stay foregrounded
  during an announce (with a ~30s background-task grace period as a safety net).
- Full App Store review polish.

## Distribution & Constraints

- **TestFlight / family.** Requires an Apple Developer account, provisioning,
  and an Xcode-based iOS app target.
- **Home Wi-Fi only.** The phone must be on the same LAN as the speakers.
- **Foreground announce.** iOS suspends the process shortly after backgrounding,
  which would kill the on-device HTTP server mid-announce. We mitigate with
  `beginBackgroundTask`/`endBackgroundTask` (~30s grace) and document the
  constraint. Stage 2 (cloud, fire-and-forget) removes it.

## Architecture

### Project structure (Approach A: SwiftPM core + Xcode app shells)

```
sonos-announce/
├── Package.swift            # defines SonosKit library (+ macOS app executable)
├── Sources/
│   └── SonosKit/            # platform-agnostic core — the valuable logic
├── Tests/
│   └── SonosKitTests/       # `swift test` — no simulator needed
├── apps/
│   ├── macOS/               # existing SwiftUI UI, thinned to call SonosKit
│   └── iOS/                 # NEW Xcode project: SonosAnnounce iOS app
└── docs/superpowers/specs/  # this design doc
```

The iOS app must be an Xcode project (TestFlight needs a signed bundle, Info.plist,
provisioning). All bug-prone logic lives in `SonosKit` so it is unit-testable
from the command line with no simulator. App shells hold only views, view models,
Info.plist, entitlements, and lifecycle.

### SonosKit modules

| Module | Role | Origin |
|---|---|---|
| `Models` | `SonosPlayer`, `SonosGroup`, `PlaybackState`, `SonosError` | port + extend |
| `SonosDiscovery` | Bonjour browse → resolve → device description | port as-is |
| `SonosTopology` | **NEW** — `GetZoneGroupState` → groups + coordinators | new |
| `SonosControlling` (protocol) + `SonosController` | UPnP/SOAP transport, volume, playback | port + protocol-ize |
| `TTSGenerator` | `AVSpeechSynthesizer` on both platforms; real duration from the written file | refactor |
| `AudioServer` | `NWListener` HTTP server, UUID filenames | port + harden |
| `AnnouncementService` (protocol) + `LocalUPnPAnnouncementService` | orchestrates the full announce flow | new |
| `SettingsStore` | `UserDefaults`-backed: saved speaker IDs, custom phrases, last volume, announcement prefix | new |

### Key design decisions

1. **`AnnouncementService` is a protocol.** Stage 1 ships
   `LocalUPnPAnnouncementService`. Stage 2's cloud path becomes
   `SonosCloudAnnouncementService` behind the same protocol; the UI never changes.
2. **`SonosController` becomes a protocol (`SonosControlling`).** Enables a mock
   for unit-testing the orchestration without real speakers.
3. **Unify TTS on `AVSpeechSynthesizer`** for both platforms, dropping the macOS
   `say`/`afconvert` subprocess path. One code path, and the duration bug is
   fixed in one place. (If the `say` voices are strongly preferred later, a
   macOS-only override can be re-added.)
4. **Duration read from the generated file** (`AVAudioFile.length /
   processingFormat.sampleRate`) instead of assuming 44.1kHz mono.

## iPhone UI / UX

Direction **B (revised)** — a custom dark "control" feel, single screen:

- **Speakers:** compact wrapping pills in a scrollable area (edge fade signals
  more below) so 9–10 rooms stay tidy. A `Select all` shortcut in the section
  header. Grouped rooms show a small `grp` tag. **Speakers display as individual
  pills** (not collapsed into group units) for transparency; behind the scenes
  commands still go to the group coordinator.
- **Message:** a single tappable card showing the current message. Tapping opens
  a bottom **sheet** with a free-text editor plus canned quick-phrase chips. The
  sheet's `Edit` manages saved phrases; `＋ Add` saves the current text as a new
  quick phrase. (This is where editable quick phrases live.)
- **Volume:** a slider (10–100).
- **Announce:** a prominent button; shows progress/disabled state while running.

The macOS app keeps its existing single-window layout, refactored to call into
`SonosKit`.

## Data Flow: the announce

In `LocalUPnPAnnouncementService.announce(...)`:

1. Resolve selected speaker IDs → players.
2. Map players → their group **coordinators** via `SonosTopology`, **deduped**
   (a grouped Kitchen+Living Room → one command to the coordinator).
3. Generate TTS once (`AVSpeechSynthesizer`) → WAV data + **real duration**.
4. Determine local IP; start `AudioServer` with a UUID filename.
5. Snapshot each target coordinator's playback state.
6. Set volume + URI + play on coordinators **concurrently** (`withTaskGroup`) so
   rooms fire together rather than staggered.
7. Wait for completion (poll coordinator transport, bounded by real duration +
   timeout).
8. **Restore** each coordinator's snapshot.
9. Stop the server.

### Grouping mechanics

`SonosTopology` calls `GetZoneGroupState` (ZoneGroupTopology service) on any one
discovered player. The returned XML lists zone groups, each with a coordinator
UUID and member zones. From this we build `[SonosGroup]` and a map from player
UUID → coordinator player. Announcements target coordinators only.

### iOS lifecycle

- Wrap the announce flow in `beginBackgroundTask`/`endBackgroundTask` for ~30s of
  grace if backgrounded mid-announce.
- First discovery triggers the iOS local-network permission prompt. On denial,
  show an explainer + "Open Settings" button rather than silently failing.

## Error Handling

- **Partial success:** each coordinator is isolated. One failing room is reported
  as failed while others still announce. Status summarizes
  (e.g., "Announced to 3 of 4 — Bedroom unreachable"). This replaces the
  original app's abort-on-first-error behavior.
- **Guaranteed best-effort restore:** restore runs via a guaranteed path
  (`defer`-style) so a mid-flow error never leaves speakers stuck on the
  announcement.
- **Typed errors:** extend `SonosError` with `discoveryFailed`,
  `permissionDenied`, `noLocalIP`, `ttsGenerationFailed`, `soapFailed`, each with
  a user-facing message.
- **Timeouts:** SOAP calls (10s) and `waitForCompletion` are bounded.

## Testing Strategy

All unit tests run via `swift test` against `SonosKit` (no simulator):

- **Pure logic:** XML extract/escape/unescape; `ZoneGroupState` parsing → groups
  & coordinators (fixture XML); SOAP envelope construction; HTTP Range request
  parsing in `AudioServer`; audio-duration-from-file; `SettingsStore` round-trip.
- **Orchestration:** `AnnouncementService` against a mock `SonosControlling` +
  mock topology — verifies coordinator targeting, group dedup, concurrent play,
  and guaranteed restore on failure.
- **Manual / integration:** real speakers via TestFlight (the irreducible test).

## Feature Scope (v1)

In scope:

- Core: discover → select speakers → pick/type message → volume → announce →
  restore.
- Persisted settings (selected speakers, last volume, last message, phrases).
- Editable quick phrases (in the message sheet).
- Correct grouped-speaker handling (target coordinators).
- iOS audio-duration fix (real duration from file).
- Partial-success error handling + guaranteed restore.

Deferred to Stage 2:

- Sonos cloud `audioClip` API, OAuth, backend, remote announce, robust background
  operation, S2-capability detection.

## Open Items for the Implementation Plan

- Exact `Package.swift` target wiring for the macOS executable + `SonosKit`
  library, and the iOS Xcode project's local-package reference.
- Whether the macOS app stays a SwiftPM executable or becomes a small Xcode
  target (defer; either works with the shared library).
- The announcement prefix ("Family announcement! …" in the original) becomes a
  configurable `SettingsStore` value, default on.
