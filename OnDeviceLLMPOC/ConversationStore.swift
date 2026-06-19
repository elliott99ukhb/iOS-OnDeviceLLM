import SwiftUI
import FoundationModels

/// The brain of the Chat tab.
///
/// Owns a stateful `LanguageModelSession` (the model's working memory) and
/// mirrors it into `messages` for display. After every turn the whole
/// `Transcript` is written to disk as JSON; on launch we decode it and rebuild
/// the session with `LanguageModelSession(transcript:)`, so conversations — and
/// the model's memory of them — survive being force-quit.
@MainActor
@Observable
final class ConversationStore {
    /// On-screen bubbles. The streaming reply is the last element, mutated in place.
    private(set) var messages: [ChatMessage] = []
    private(set) var isResponding = false

    /// Generation knobs; saved whenever they change.
    var settings: GenerationSettings {
        didSet { settings.save() }
    }

    /// The system prompt. Takes effect on the next `newConversation()`.
    var instructions: String {
        didSet { UserDefaults.standard.set(instructions, forKey: Keys.instructions) }
    }

    private var session: LanguageModelSession
    private var generationTask: Task<Void, Never>?

    private enum Keys {
        static let instructions = "systemInstructions"
    }

    static let defaultInstructions =
        "You are a helpful, knowledgeable assistant running entirely on-device. "
        + "Give clear, well-structured answers. Use the earlier conversation for context, "
        + "and ask a brief clarifying question when a request is ambiguous."

    init() {
        let savedInstructions =
            UserDefaults.standard.string(forKey: Keys.instructions) ?? Self.defaultInstructions
        self.settings = .load()
        self.instructions = savedInstructions

        if let transcript = Self.loadTranscript() {
            self.session = LanguageModelSession(transcript: transcript)
            self.messages = ChatMessage.bubbles(from: transcript)
        } else {
            self.session = LanguageModelSession(instructions: savedInstructions)
        }
    }

    // MARK: - Sending

    /// Appends the user's turn and kicks off a cancellable streaming reply.
    func submit(_ rawText: String, image: UIImage?) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || image != nil else { return }
        guard !isResponding else { return }

        // If the user only attached a photo, give the model something to do.
        let promptText = text.isEmpty ? "What's in this image? Describe it." : text

        messages.append(ChatMessage(role: .user, text: text, image: image))
        let replyID = UUID()
        messages.append(ChatMessage(id: replyID, role: .assistant, text: ""))

        start(promptText: promptText, image: image, replyID: replyID)
    }

    /// Cancels the in-flight response. Any text streamed so far is kept.
    func stop() {
        generationTask?.cancel()
    }

    private func start(promptText: String, image: UIImage?, replyID: UUID) {
        isResponding = true
        generationTask = Task {
            await generate(promptText: promptText, image: image, replyID: replyID, allowRollover: true)
            isResponding = false
            generationTask = nil
            persist()
        }
    }

    private func generate(promptText: String, image: UIImage?, replyID: UUID, allowRollover: Bool) async {
        let options = settings.generationOptions
        do {
            if let image, let cgImage = image.modelCGImage {
                // Multimodal prompt: an image attachment plus the question.
                let stream = session.streamResponse(options: options) {
                    Attachment(cgImage)
                    promptText
                }
                for try await partial in stream {
                    if Task.isCancelled { break }
                    update(replyID, text: partial.content)
                }
            } else {
                let stream = session.streamResponse(to: promptText, options: options)
                for try await partial in stream {
                    if Task.isCancelled { break }
                    update(replyID, text: partial.content)
                }
            }
            if Task.isCancelled { markStopped(replyID) }
        } catch is CancellationError {
            markStopped(replyID)
        } catch let error as LanguageModelSession.GenerationError {
            // The on-device context window is small; when a long chat overflows we
            // condense the history into a fresh session and retry once, so the
            // conversation keeps working instead of erroring on every message.
            if case .exceededContextWindowSize = error, allowRollover, !Task.isCancelled {
                await rollOverContext()
                await generate(promptText: promptText, image: image, replyID: replyID, allowRollover: false)
            } else if Task.isCancelled {
                markStopped(replyID)
            } else {
                update(replyID, text: "⚠️ \(error.localizedDescription)", isError: true)
            }
        } catch {
            if Task.isCancelled { markStopped(replyID) }
            else { update(replyID, text: "⚠️ \(error.localizedDescription)", isError: true) }
        }
    }

    private func update(_ id: UUID, text: String, isError: Bool = false) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text = text
        messages[index].isError = isError
    }

    private func markStopped(_ id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        if messages[index].text.isEmpty {
            messages[index].text = "_Stopped._"
        }
    }

    // MARK: - Context rollover

    /// Replaces the full session with a fresh one seeded by a short summary of the
    /// conversation so far, freeing up the context window.
    private func rollOverContext() async {
        // Exclude the in-flight user message + empty reply bubble.
        let prior = Array(messages.dropLast(2))
        let summary = await summarize(prior)
        let seeded = instructions
            + "\n\nSummary of the conversation so far (older messages were condensed "
            + "to fit on-device memory):\n" + summary
        session = LanguageModelSession(instructions: seeded)
    }

    private func summarize(_ msgs: [ChatMessage]) async -> String {
        let digest = msgs.suffix(12).map { m in
            let who = m.role == .user ? "User" : "Assistant"
            return "\(who): \(m.text.prefix(400))"
        }.joined(separator: "\n")
        guard !digest.isEmpty else { return "(no prior context)" }

        do {
            let summarizer = LanguageModelSession(
                instructions: "You summarize conversations into concise, factual notes."
            )
            let response = try await summarizer.respond(
                to: "Summarize the key facts, decisions, and context from this conversation "
                    + "so it can be continued. Use short bullet points:\n\n\(digest)",
                options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 240)
            )
            return response.content
        } catch {
            // Fall back to the raw recent digest if summarizing fails.
            return digest
        }
    }

    // MARK: - Regenerate

    /// Re-runs the prompt that produced the last assistant reply, after rolling the
    /// session's memory back one turn so the new answer isn't biased by the old one.
    func regenerateLast() {
        guard !isResponding, messages.count >= 2 else { return }
        guard messages.last?.role == .assistant else { return }
        let user = messages[messages.count - 2]
        guard user.role == .user else { return }

        // Drop the last prompt + response from the model's memory.
        let trimmed = Transcript(entries: session.transcript.dropLast(2))
        session = LanguageModelSession(transcript: trimmed)
        messages.removeLast(2)

        submit(user.text, image: user.image)
    }

    // MARK: - Conversation lifecycle

    /// Reduces first-token latency by spinning the model up ahead of time.
    func prewarm() {
        session.prewarm()
    }

    /// Clears the screen and the model's memory, applying the current instructions.
    func newConversation() {
        generationTask?.cancel()
        session = LanguageModelSession(instructions: instructions)
        messages = []
        isResponding = false
        try? FileManager.default.removeItem(at: Self.transcriptURL)
    }

    // MARK: - Persistence

    private static let transcriptURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("conversation.json")
    }()

    /// Encodes + writes off the main actor so long histories don't hitch the UI.
    private func persist() {
        let transcript = session.transcript
        let url = Self.transcriptURL
        Task.detached(priority: .background) {
            do {
                let data = try JSONEncoder().encode(transcript)
                try data.write(to: url, options: .atomic)
            } catch {
                print("ConversationStore: failed to persist transcript — \(error)")
            }
        }
    }

    private static func loadTranscript() -> Transcript? {
        guard
            let data = try? Data(contentsOf: transcriptURL),
            let transcript = try? JSONDecoder().decode(Transcript.self, from: data),
            !transcript.isEmpty
        else {
            return nil
        }
        return transcript
    }
}
