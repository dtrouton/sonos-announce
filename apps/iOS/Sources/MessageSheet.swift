import SwiftUI
import SonosKit

/// Bottom sheet for composing the announcement. Type freely or tap a saved
/// quick phrase to fill it in. Saved phrases can be added (from the current
/// text) and deleted; changes persist via the bound `phrases` array.
struct MessageSheet: View {
    @Binding var message: String
    @Binding var phrases: [String]
    @Binding var prefixEnabled: Bool
    let onUse: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Type a message…", text: $message, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

                HStack {
                    Text("Quick phrases").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(editing ? "Done" : "Edit") { editing.toggle() }
                        .font(.caption)
                }

                FlowLayout(spacing: 8) {
                    ForEach(phrases, id: \.self) { phrase in
                        chip(phrase)
                    }
                    if !editing { addChip }
                }

                Spacer()

                Toggle(isOn: $prefixEnabled) {
                    Text("Start with \u{201C}Family announcement!\u{201D}")
                        .font(.callout)
                }

                Button(action: { onUse(); dismiss() }) {
                    Text("Use this message")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(message.isEmpty)
            }
            .padding()
            .navigationTitle("Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func chip(_ phrase: String) -> some View {
        HStack(spacing: 6) {
            Text(phrase).font(.callout)
            if editing {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .onTapGesture { phrases.removeAll { $0 == phrase } }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.quaternary, in: Capsule())
        .onTapGesture {
            guard !editing else { return }
            message = phrase
        }
    }

    private var addChip: some View {
        Button {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !phrases.contains(trimmed) else { return }
            phrases.append(trimmed)
        } label: {
            Label("Add", systemImage: "plus")
                .font(.callout)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.tint.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
