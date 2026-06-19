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

    func send(_ rawText: String, image: UIImage?) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || image != nil else { return }
        guard !isResponding else { return }

        // If the user only attached a photo, give the model something to do.
        let promptText = text.isEmpty ? "What's in this image? Describe it." : text

        messages.append(ChatMessage(role: .user, text: text, image: image))
        let replyID = UUID()
        messages.append(ChatMessage(id: replyID, role: .assistant, text: ""))
        isResponding = true
        defer { isResponding = false }

        let options = settings.generationOptions

        do {
            if let image, let cgImage = image.modelCGImage {
                // Multimodal prompt: an image attachment plus the question.
                let stream = session.streamResponse(options: options) {
                    Attachment(cgImage)
                    promptText
                }
                for try await partial in stream {
                    update(replyID, text: partial.content)
                }
            } else {
                let stream = session.streamResponse(to: promptText, options: options)
                for try await partial in stream {
                    update(replyID, text: partial.content)
                }
            }
        } catch {
            update(replyID, text: "⚠️ \(error.localizedDescription)", isError: true)
        }

        persist()
    }

    private func update(_ id: UUID, text: String, isError: Bool = false) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text = text
        messages[index].isError = isError
    }

    // MARK: - Conversation lifecycle

    /// Reduces first-token latency by spinning the model up ahead of time.
    func prewarm() {
        session.prewarm()
    }

    /// Clears the screen and the model's memory, applying the current instructions.
    func newConversation() {
        session = LanguageModelSession(instructions: instructions)
        messages = []
        try? FileManager.default.removeItem(at: Self.transcriptURL)
    }

    // MARK: - Persistence

    private static let transcriptURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("conversation.json")
    }()

    private func persist() {
        do {
            let data = try JSONEncoder().encode(session.transcript)
            try data.write(to: Self.transcriptURL, options: .atomic)
        } catch {
            // Persistence is best-effort; the in-memory session is still intact.
            print("ConversationStore: failed to persist transcript — \(error)")
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
