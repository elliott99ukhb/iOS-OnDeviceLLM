import SwiftUI

/// Sheet for tuning generation and editing the system prompt. Bound directly to
/// the store so changes apply live (generation knobs) or on the next new
/// conversation (instructions).
struct ChatSettingsView: View {
    @Bindable var store: ConversationStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(store.settings.temperature, format: .number.precision(.fractionLength(2)))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $store.settings.temperature, in: 0...1, step: 0.01)
                        Text("Lower is focused and repeatable; higher is more creative.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Style", selection: $store.settings.sampling) {
                        ForEach(GenerationSettings.Sampling.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Max length")
                            Spacer()
                            Text(store.settings.maxResponseTokens <= 0
                                 ? "Unlimited"
                                 : "\(Int(store.settings.maxResponseTokens)) tokens")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $store.settings.maxResponseTokens, in: 0...4096, step: 32)
                    }

                    Button("Reset to defaults") {
                        store.settings = GenerationSettings()
                    }
                } header: {
                    Text("Response")
                } footer: {
                    Text("Applied to every message you send.")
                }

                Section {
                    TextEditor(text: $store.instructions)
                        .frame(minHeight: 110)
                        .font(.callout)
                } header: {
                    Text("System instructions")
                } footer: {
                    Text("Steers the assistant's persona and rules. Takes effect when you start a new conversation.")
                }

                Section {
                    Button(role: .destructive) {
                        store.newConversation()
                        dismiss()
                    } label: {
                        Label("Start new conversation", systemImage: "square.and.pencil")
                    }
                }
            }
            .navigationTitle("Chat settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
