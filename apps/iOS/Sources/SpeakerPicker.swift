import SwiftUI
import SonosKit

/// Compact wrapping pills for speaker selection, with a "grp" badge for players
/// in a multi-member group and a Select-all / None shortcut in the header.
struct SpeakerPicker: View {
    let players: [SonosPlayer]
    let groupedIDs: Set<String>
    let isSearching: Bool
    @Binding var selected: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Speakers · \(selected.count) selected")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                if !players.isEmpty {
                    Button(selected.count == players.count ? "None" : "Select all") {
                        selected = selected.count == players.count ? [] : Set(players.map(\.id))
                    }
                    .font(.caption).buttonStyle(.plain).foregroundStyle(.tint)
                }
            }

            if isSearching {
                ProgressView().frame(maxWidth: .infinity)
            } else if players.isEmpty {
                Text("No speakers found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    FlowLayout(spacing: 8) {
                        ForEach(players) { player in
                            pill(for: player)
                        }
                    }
                }
                .frame(maxHeight: 180)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.88),
                            .init(color: .clear, location: 1.0),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func pill(for player: SonosPlayer) -> some View {
        let isOn = selected.contains(player.id)
        Button {
            if isOn { selected.remove(player.id) } else { selected.insert(player.id) }
        } label: {
            HStack(spacing: 6) {
                Text(player.name)
                if groupedIDs.contains(player.id) {
                    Text("grp")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.white.opacity(0.25), in: Capsule())
                }
            }
            .font(.callout)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.1)),
                        in: Capsule())
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
    }
}
