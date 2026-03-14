import SwiftUI

struct ContentView: View {
    @StateObject private var discovery = SonosDiscovery()
    @State private var selectedPlayers: Set<String> = []  // Set of player IDs
    @State private var message = ""
    @State private var customMessage = ""

    private let quickPhrases = [
        "Time to get ready for school!",
        "Dinner time!",
        "Come downstairs!",
        "Have a shower!",
    ]
    @State private var volume: Double = 50
    @State private var status = ""
    @State private var isAnnouncing = false

    private let controller = SonosController()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sonos Announce")
                .font(.largeTitle)
                .fontWeight(.bold)

            // -- Speakers --
            GroupBox("Speakers") {
                VStack(alignment: .leading, spacing: 0) {
                    if discovery.isSearching {
                        ProgressView("Searching...")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else if discovery.players.isEmpty {
                        Text("No speakers found")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ForEach(discovery.players) { player in
                            let isSelected = selectedPlayers.contains(player.id)
                            Button {
                                if isSelected {
                                    selectedPlayers.remove(player.id)
                                } else {
                                    selectedPlayers.insert(player.id)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: isSelected
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(isSelected ? .accentColor : .secondary)
                                    Text(player.name)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(
                                isSelected
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.clear
                            )
                            .cornerRadius(6)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    HStack {
                        Button("Refresh") {
                            Task { await discovery.discover() }
                        }
                        .disabled(discovery.isSearching)

                        Spacer()

                        if !discovery.players.isEmpty {
                            Button("Select All") {
                                selectedPlayers = Set(discovery.players.map(\.id))
                            }
                            Button("None") {
                                selectedPlayers.removeAll()
                            }
                        }
                    }
                }
            }

            // -- Message --
            GroupBox("Message") {
                VStack(alignment: .leading, spacing: 6) {
                    FlowLayout(spacing: 6) {
                        ForEach(quickPhrases, id: \.self) { phrase in
                            Button {
                                message = phrase
                                customMessage = ""
                            } label: {
                                Text(phrase)
                                    .font(.callout)
                                    .fixedSize()
                            }
                            .buttonStyle(.bordered)
                            .tint(message == phrase && customMessage.isEmpty ? .accentColor : .secondary)
                        }
                    }

                    Divider()

                    TextField("Or type something...", text: $customMessage)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: customMessage) { _ in
                            if !customMessage.isEmpty {
                                message = customMessage
                            }
                        }
                }
            }

            // -- Volume --
            GroupBox("Volume") {
                HStack {
                    Image(systemName: "speaker.fill")
                    Slider(value: $volume, in: 10...100, step: 5)
                    Text("\(Int(volume))")
                        .monospacedDigit()
                        .frame(width: 30)
                }
            }

            // -- Announce button --
            Button {
                Task { await announce() }
            } label: {
                HStack {
                    if isAnnouncing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Image(systemName: "megaphone.fill")
                    Text(isAnnouncing ? "Announcing..." : "Announce!")
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(selectedPlayers.isEmpty || isAnnouncing || message.isEmpty)

            // -- Status --
            if !status.isEmpty {
                Text(status)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 400)
        .onAppear {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        #endif
        .task {
            await discovery.discover()
        }
    }

    // MARK: - Announce Flow

    private func announce() async {
        let players = discovery.players.filter { selectedPlayers.contains($0.id) }
        guard !players.isEmpty else { return }

        isAnnouncing = true
        defer { isAnnouncing = false }

        do {
            // 1. Generate TTS audio (once, shared across all speakers)
            status = "Generating audio..."
            let fullMessage = "Family announcement! \(message)"
            let audioData = try await TTSGenerator.generate(text: fullMessage)
            let audioDuration = Double(audioData.count - 44) / (44100.0 * 2.0)

            guard let localIP = getLocalIPAddress() else {
                throw SonosError.noLocalIP
            }

            let server = AudioServer()
            try await server.start(data: audioData)
            defer { server.stop() }

            let audioURL = "http://\(localIP):\(server.port)/announce.wav"

            let names = players.map(\.name).joined(separator: ", ")
            status = "Announcing to \(names)..."

            var snapshots: [(SonosPlayer, PlaybackState)] = []
            for player in players {
                let state = try await controller.snapshot(player: player)
                snapshots.append((player, state))
            }

            for player in players {
                try await controller.announce(player: player, audioURL: audioURL, volume: Int(volume))
            }

            try await controller.waitForCompletion(player: players[0], audioDuration: audioDuration)

            status = "Restoring playback..."
            for (player, state) in snapshots {
                try await controller.restore(player: player, state: state)
            }

            status = "Done!"
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            status = ""

        } catch {
            status = "Error: \(error.localizedDescription)"
        }
    }
}
