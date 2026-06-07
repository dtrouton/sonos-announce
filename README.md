# Sonos Announce

A lightweight macOS app that sends text-to-speech announcements to Sonos speakers on your local network. Select speakers, pick a message (or type your own), and hit announce — your Sonos speakers will pause what they're playing, broadcast the message, then resume playback.

## How It Works

1. **Discovers** Sonos speakers on the LAN via Bonjour (`_sonos._tcp`)
2. **Generates** a WAV audio file from your message using macOS `say` (or `AVSpeechSynthesizer` on iOS)
3. **Serves** the audio over a temporary local HTTP server so speakers can fetch it
4. **Snapshots** each speaker's current playback state (track, position, volume)
5. **Plays** the announcement on all selected speakers via UPnP/SOAP
6. **Restores** each speaker's previous state once the announcement finishes

## Requirements

- macOS 13+ (Ventura) or iOS 16+
- Sonos speakers on the same local network
- Swift 5.9+

## Building

```bash
swift build
```

Or open the project in Xcode and build the `SonosAnnounce` target.

## Testing

```bash
swift test
```

Runs the SonosKit unit tests (no speakers or simulator required).

## Running

```bash
swift run SonosAnnounce
```

The app will open a window where you can:

- **Select speakers** — discovered automatically on launch; use Refresh to re-scan
- **Choose a message** — pick a quick phrase or type a custom one
- **Set volume** — controls the announcement volume (10–100)
- **Announce** — sends the message to all selected speakers

## Architecture

The project is split into a shared library and a per-platform app shell:

- `Sources/SonosKit/` — platform-agnostic core library (all the Sonos logic), unit-tested via `swift test`:
  - `Models.swift` — `SonosPlayer`, `PlaybackState`, `SonosGroup`, `SonosError`, `AnnounceResult`
  - `SonosDiscovery.swift` — Bonjour discovery → IP resolution → device description
  - `SonosControlling.swift` — `SonosControlling` protocol + `SonosController` (UPnP/SOAP transport, volume, playback)
  - `SonosTopology.swift` — parses `GetZoneGroupState` into zone groups + coordinators
  - `CoordinatorResolver.swift` — maps selected players to their deduplicated group coordinators
  - `TTSGenerator.swift` — text-to-speech via `AVSpeechSynthesizer`; `wavDuration` parsing
  - `AudioServer.swift` — ephemeral HTTP server that serves the WAV to speakers (+ Range support)
  - `AudioPreparer.swift` — `AudioPreparing` + `LocalAudioPreparer` (TTS → server → URL)
  - `AnnouncementService.swift` — orchestrates the announce flow (resolve → snapshot → play → restore) with partial-success handling
  - `SettingsStore.swift` — `UserDefaults`-backed settings (selected speakers, volume, quick phrases, prefix)
  - `NetworkUtilities.swift` — local IP detection helpers
  - `XMLUtilities.swift` — XML parsing helpers
- `apps/macOS/` — the macOS SwiftUI app (`SonosAnnounceApp.swift`, `ContentView.swift`, `FlowLayout.swift`, `Info.plist`) that consumes `SonosKit`.

## Network Requirements

The app needs local network access for:

- **mDNS/Bonjour** — to discover Sonos devices
- **HTTP (port 1400)** — to send UPnP commands to speakers
- **HTTP (ephemeral port)** — to serve audio files to speakers

If running in a sandboxed environment, ensure the app has local network permissions.
