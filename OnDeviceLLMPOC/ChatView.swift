import SwiftUI
import PhotosUI

/// Capability 1 — Streaming, multi-turn chat with memory.
///
/// A real conversation UI: every turn is kept on screen, the reply streams in
/// token-by-token, the whole thing is remembered across launches, and you can
/// attach a photo to ask about it (on-device multimodal, iOS 27).
struct ChatView: View {
    @State private var store = ConversationStore()
    @State private var input = ""
    @State private var pickedItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var showSettings = false
    @State private var showScrollToBottom = false

    private let bottomAnchor = "bottom"

    private let starters = [
        "Explain how on-device AI works, simply.",
        "Write a haiku about the sea.",
        "Plan a relaxed weekend in London.",
        "Give me 3 pasta dinner ideas."
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcript
                Divider()
                composer
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { store.newConversation() } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(store.messages.isEmpty)
                    .accessibilityLabel("New conversation")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                ChatSettingsView(store: store)
            }
        }
        .task { store.prewarm() }
        .onChange(of: pickedItem) { _, item in
            Task { await loadAttachment(item) }
        }
        .onChange(of: store.isResponding) { wasResponding, nowResponding in
            if wasResponding && !nowResponding { haptic(.soft) }   // reply finished
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if store.messages.isEmpty {
                    emptyState
                        .padding(.top, 60)
                        .padding(.horizontal)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(store.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                                .contextMenu { menu(for: message) }
                        }
                        Color.clear.frame(height: 1).id(bottomAnchor)
                    }
                    .padding()
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.containerSize.height < geo.contentSize.height - 80
            } action: { _, isAwayFromBottom in
                showScrollToBottom = isAwayFromBottom
            }
            .onChange(of: store.messages.last?.text) { _, _ in scrollToBottom(proxy) }
            .onChange(of: store.messages.count) { _, _ in scrollToBottom(proxy) }
            .overlay(alignment: .bottomTrailing) {
                if showScrollToBottom {
                    Button { scrollToBottom(proxy) } label: {
                        Image(systemName: "arrow.down")
                            .font(.body.weight(.semibold))
                            .padding(10)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().stroke(.quaternary))
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showScrollToBottom)
        }
    }

    @ViewBuilder
    private func menu(for message: ChatMessage) -> some View {
        if !message.text.isEmpty {
            Button {
                UIPasteboard.general.string = message.text
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
        if message.role == .assistant,
           message.id == store.messages.last?.id,
           !store.isResponding {
            Button {
                haptic(.light)
                store.regenerateLast()
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            ContentUnavailableView {
                Label("Start chatting", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("Ask anything and watch the on-device model stream its reply. "
                     + "Attach a photo to ask about an image. Your conversation is remembered between launches.")
            }

            VStack(spacing: 8) {
                ForEach(starters, id: \.self) { starter in
                    Button {
                        sendStarter(starter)
                    } label: {
                        Text(starter)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground),
                                        in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 8) {
            if let pendingImage {
                attachmentPreview(pendingImage)
            }

            HStack(alignment: .bottom, spacing: 10) {
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .frame(width: 36, height: 36)
                }
                .disabled(store.isResponding)

                // TextField(axis: .vertical) is the modern Apple component for a
                // chat input that grows with the text; we give it a comfortable
                // height and a rounded fill instead of the cramped .roundedBorder.
                TextField("Message", text: $input, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...6)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(minHeight: 38)
                    .background(Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 19))
                    .overlay(
                        RoundedRectangle(cornerRadius: 19)
                            .stroke(Color(.separator).opacity(0.6), lineWidth: 0.5)
                    )
                    .onSubmit(send)

                Button(action: store.isResponding ? stop : send) {
                    Image(systemName: store.isResponding ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(!store.isResponding && !canSend)
                .accessibilityLabel(store.isResponding ? "Stop" : "Send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func attachmentPreview(_ image: UIImage) -> some View {
        HStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("Photo attached")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                pendingImage = nil
                pickedItem = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canSend: Bool {
        guard !store.isResponding else { return false }
        return !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingImage != nil
    }

    // MARK: - Actions

    private func send() {
        guard canSend else { return }
        let text = input
        let image = pendingImage
        input = ""
        pendingImage = nil
        pickedItem = nil
        haptic(.light)
        store.submit(text, image: image)
    }

    private func stop() {
        haptic(.rigid)
        store.stop()
    }

    private func sendStarter(_ text: String) {
        haptic(.light)
        store.submit(text, image: nil)
    }

    private func loadAttachment(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            pendingImage = image.downscaled()
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

#Preview {
    ChatView()
}
