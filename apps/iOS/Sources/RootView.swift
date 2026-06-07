import SwiftUI
import UIKit
import SonosKit

struct RootView: View {
    @StateObject private var discovery = SonosDiscovery()
    @State private var selected: Set<String> = []
    @State private var groupedIDs: Set<String> = []
    @State private var message = ""
    @State private var phrases: [String] = SettingsStore.defaultPhrases
    @State private var volume: Double = 50
    @State private var prefixEnabled = true
    @State private var status = ""
    @State private var isAnnouncing = false
    @State private var showingSheet = false

    private let settings = SettingsStore()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.10), Color(white: 0.16)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("📣 Announce").font(.largeTitle.bold())
                    Spacer()
                    Button { Task { await refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(discovery.isSearching)
                }

                SpeakerPicker(players: discovery.players, groupedIDs: groupedIDs,
                              isSearching: discovery.isSearching, selected: $selected)

                if !discovery.isSearching && discovery.players.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.exclamationmark")
                        Text("No speakers found. If you denied Local Network access, enable it in Settings.")
                            .font(.caption)
                        Button("Open Settings", action: openSettings)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }

                Button { showingSheet = true } label: {
                    HStack {
                        Text(message.isEmpty ? "Tap to write a message" : message)
                            .foregroundStyle(message.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "pencil").foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Volume · \(Int(volume))").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Image(systemName: "speaker.fill")
                        Slider(value: $volume, in: 10...100, step: 5)
                    }
                }

                Spacer()

                if !status.isEmpty {
                    Text(status).font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Button { Task { await announce() } } label: {
                    HStack {
                        if isAnnouncing { ProgressView().tint(.white) }
                        Image(systemName: "megaphone.fill")
                        Text(isAnnouncing ? "Announcing…" : "Announce")
                    }
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty || message.isEmpty || isAnnouncing)
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
        .tint(Color(red: 0.04, green: 0.52, blue: 1.0))
        .sheet(isPresented: $showingSheet) {
            MessageSheet(message: $message, phrases: $phrases, prefixEnabled: $prefixEnabled,
                         onUse: { settings.quickPhrases = phrases })
                .presentationDetents([.medium, .large])
        }
        .task {
            selected = settings.selectedPlayerIDs
            volume = Double(settings.lastVolume)
            phrases = settings.quickPhrases
            message = settings.lastMessage
            prefixEnabled = settings.prefixEnabled
            await refresh()
        }
        .onChange(of: selected) { _ in settings.selectedPlayerIDs = selected }
        .onChange(of: volume) { _ in settings.lastVolume = Int(volume) }
        .onChange(of: prefixEnabled) { _ in settings.prefixEnabled = prefixEnabled }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func refresh() async {
        await discovery.discover()
        if let probe = discovery.players.first {
            let groups = (try? await SonosTopology().fetchGroups(from: probe)) ?? []
            groupedIDs = groupedPlayerIDs(from: groups)
        }
    }

    private func announce() async {
        let players = discovery.players.filter { selected.contains($0.id) }
        guard !players.isEmpty, !message.isEmpty else { return }

        isAnnouncing = true
        defer { isAnnouncing = false }
        settings.lastMessage = message

        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "announce") {
            if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask); bgTask = .invalid }
        }
        defer { if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) } }

        let full = settings.prefixEnabled ? "Family announcement! \(message)" : message
        let service = LocalUPnPAnnouncementService(
            controller: SonosController(),
            resolver: LiveCoordinatorResolver(known: discovery.players),
            audioPreparer: LocalAudioPreparer()
        )

        status = "Announcing…"
        let result = await service.announce(message: full, to: players, volume: Int(volume))
        status = announceStatusMessage(result)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        status = ""
    }
}
