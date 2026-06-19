import SwiftUI
import FoundationModels

/// One turn in the on-screen conversation. This is a *display* model — the
/// authoritative memory lives in the session's `Transcript`. We rebuild an
/// array of these from the transcript when restoring a saved conversation.
struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }

    let id: UUID
    let role: Role
    var text: String
    var image: UIImage?
    var isError: Bool

    init(id: UUID = UUID(), role: Role, text: String, image: UIImage? = nil, isError: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.image = image
        self.isError = isError
    }
}

extension ChatMessage {
    /// Projects a restored `Transcript` into the user/assistant bubbles we show.
    /// Instructions, tool calls/outputs and reasoning entries are intentionally
    /// skipped — they're part of the model's context, not the chat UI.
    static func bubbles(from transcript: Transcript) -> [ChatMessage] {
        transcript.compactMap { entry in
            switch entry {
            case .prompt(let prompt):
                let text = Self.text(in: prompt.segments)
                let image = Self.firstImage(in: prompt.segments)
                guard !text.isEmpty || image != nil else { return nil }
                return ChatMessage(role: .user, text: text, image: image)

            case .response(let response):
                let text = Self.text(in: response.segments)
                guard !text.isEmpty else { return nil }
                return ChatMessage(role: .assistant, text: text)

            default:
                return nil
            }
        }
    }

    private static func text(in segments: [Transcript.Segment]) -> String {
        segments.compactMap { segment in
            if case .text(let textSegment) = segment { return textSegment.content }
            return nil
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstImage(in segments: [Transcript.Segment]) -> UIImage? {
        for segment in segments {
            if case .attachment(let attachment) = segment,
               case .image(let imageAttachment) = attachment.content {
                return UIImage(cgImage: imageAttachment.cgImage)
            }
        }
        return nil
    }
}
