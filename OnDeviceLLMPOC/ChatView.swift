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
                    Button {
                        store.newConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(store.messages.isEmpty || store.isResponding)
                    .accessibilityLabel("New conversation")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
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
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if store.messages.isEmpty {
                    emptyState
                        .padding(.top, 80)
                        .padding(.horizontal)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(store.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        Color.clear.frame(height: 1).id(bottomAnchor)
                    }
                    .padding()
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.messages.last?.text) { _, _ in scrollToBottom(proxy) }
            .onChange(of: store.messages.count) { _, _ in scrollToBottom(proxy) }
        }
    }

    private let bottomAnchor = "bottom"

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Start chatting", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Ask anything and watch the on-device model stream its reply. "
                 + "Attach a photo to ask about an image. Your conversation is remembered between launches.")
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 8) {
            if let pendingImage {
                attachmentPreview(pendingImage)
            }

            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title3)
                }
                .disabled(store.isResponding)

                TextField("Message", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .onSubmit(send)

                Button(action: send) {
                    if store.isResponding {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                    }
                }
                .disabled(!canSend)
            }
        }
        .padding([.horizontal, .bottom])
        .padding(.top, 8)
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
        Task { await store.send(text, image: image) }
    }

    private func loadAttachment(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            pendingImage = image.downscaled()
        }
    }
}

#Preview {
    ChatView()
}
