import SwiftUI

/// A single chat bubble. User turns are trailing/tinted, assistant turns are
/// leading/grey. An empty assistant bubble shows a spinner (reply in flight).
struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom) {
            if isUser { Spacer(minLength: 48) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if let image = message.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 220, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                if !message.text.isEmpty {
                    Text(rendered)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(background)
                        .foregroundStyle(message.isError ? Color.red : (isUser ? .white : .primary))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                } else if message.role == .assistant {
                    ProgressView()
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                }
            }

            if !isUser { Spacer(minLength: 48) }
        }
    }

    private var background: Color {
        if message.isError { return Color.red.opacity(0.12) }
        return isUser ? Color.accentColor : Color(.secondarySystemBackground)
    }

    /// Assistant replies are rendered as Markdown (the model emits **bold**,
    /// lists, `code`, etc.); user text and errors stay literal. Whitespace is
    /// preserved so line breaks survive, and partial/unterminated Markdown from a
    /// mid-stream reply degrades gracefully to plain text.
    private var rendered: AttributedString {
        guard message.role == .assistant, !message.isError else {
            return AttributedString(message.text)
        }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: message.text, options: options))
            ?? AttributedString(message.text)
    }
}
