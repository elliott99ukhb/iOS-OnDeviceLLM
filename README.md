# On-Device LLM Chat (Apple Foundation Models)

A focused SwiftUI chat app built on Apple's **Foundation Models** framework —
the fully on-device LLM in iOS 27. Everything runs locally on the Neural Engine:
**no API key, no network, no cost, nothing leaves the device.**

<p align="center">
  <img src="OnDeviceLLMPOC/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="120" alt="App icon"/>
</p>

## Features

- **Streaming, multi-turn chat** — replies stream in token-by-token; every turn
  stays on screen in chat bubbles.
- **Memory that survives launches** — the whole `Transcript` is saved to disk as
  JSON after each turn and rehydrated on launch via
  `LanguageModelSession(transcript:)`, so the model remembers earlier turns even
  after a force-quit. "New conversation" clears it.
- **Multimodal image input** — attach a photo with the 🖼️ button and ask about it.
  The image is sent as an `Attachment(cgImage:)` alongside your text.
- **Tunable generation** — a settings sheet exposes temperature, response style
  (Balanced / Precise / Creative → sampling mode) and max length, mapped to
  `GenerationOptions`. Preferences persist.
- **Editable system instructions** — change the assistant's persona/rules; applied
  on the next new conversation.
- **Graceful gating** — if the on-device model isn't available, a friendly screen
  explains why instead of failing silently.

## Architecture

The app is deliberately small and layered. The view layer stays thin; an
`@Observable` engine owns the model session and persistence.

| File | Responsibility |
|------|----------------|
| [`OnDeviceLLMPOCApp`](OnDeviceLLMPOC/OnDeviceLLMPOCApp.swift) | App entry point |
| [`ContentView`](OnDeviceLLMPOC/ContentView.swift) / [`ModelGate`](OnDeviceLLMPOC/ModelGate.swift) | Availability gate around the chat |
| [`ConversationStore`](OnDeviceLLMPOC/ConversationStore.swift) | Owns `LanguageModelSession`, streaming, transcript persistence |
| [`ChatView`](OnDeviceLLMPOC/ChatView.swift) | Transcript list, composer, photo attach, toolbar |
| [`MessageBubble`](OnDeviceLLMPOC/MessageBubble.swift) / [`ChatMessage`](OnDeviceLLMPOC/ChatMessage.swift) | Bubble UI + display model (incl. rebuilding from a restored transcript) |
| [`GenerationSettings`](OnDeviceLLMPOC/GenerationSettings.swift) / [`ChatSettingsView`](OnDeviceLLMPOC/ChatSettingsView.swift) | Generation knobs + settings sheet |
| [`ImageUtilities`](OnDeviceLLMPOC/ImageUtilities.swift) | `UIImage` → `CGImage` + downscaling for attachments |

## Requirements

- **Xcode 27** (this repo builds against the iOS 27.0 SDK).
- A run target with Apple Intelligence **enabled** and the model downloaded:
  - an **Apple-Intelligence-capable device** (iPhone 15 Pro / 16 / 17) on iOS 27, **or**
  - the **iOS 27 simulator** on an Apple-silicon Mac whose host macOS has Apple
    Intelligence turned on.
- Deployment target: **iOS 27.0**.

> The model is shared with the host. If Apple Intelligence isn't enabled (on the
> device, or on the Mac backing the simulator), the app shows "On-Device Model
> Unavailable" and generation fails with `appleIntelligenceNotEnabled`. A physical,
> Apple-Intelligence-enabled device is the most reliable way to see live generation.

## Getting started

1. `open OnDeviceLLMPOC.xcodeproj` in Xcode 27.
2. In **Signing & Capabilities**, select your own Team (the project ships with an
   empty `DEVELOPMENT_TEAM` so you can sign with your account). The bundle id is a
   placeholder, `com.example.OnDeviceLLMPOC` — change it if it collides.
3. Pick a destination and **Run** (⌘R). No signing is needed for the simulator.

### Deploying to a device from the command line

```sh
DEV=$(xcrun devicectl list devices | awk '/physical/{print $4; exit}')

xcodebuild -project OnDeviceLLMPOC.xcodeproj -scheme OnDeviceLLMPOC \
  -destination 'generic/platform=iOS' -configuration Debug \
  -allowProvisioningUpdates build

APP=~/Library/Developer/Xcode/DerivedData/OnDeviceLLMPOC-*/Build/Products/Debug-iphoneos/OnDeviceLLMPOC.app
xcrun devicectl device install app --device "$DEV" "$APP"
xcrun devicectl device process launch --device "$DEV" com.example.OnDeviceLLMPOC
```

## API notes (iOS 27 SDK)

Verified against the real iOS 27.0 SDK — handy if you port to another version:

1. **Streaming yields a `Snapshot`, not a `String`.** `streamResponse(to:)`
   produces `ResponseStream<String>.Snapshot`; read cumulative text from
   `partial.content`.
2. **Tools return `PromptRepresentable`.** `Tool.call(...)` returns
   `some PromptRepresentable`, so a plain `String` works — there is no `ToolOutput`.
3. **`Transcript` is `Codable`.** That's what makes cross-launch memory a few
   lines: encode `session.transcript`, decode it, and reconstruct the session with
   `LanguageModelSession(transcript:)`.
4. **Images are attachments.** `Attachment(_ cgImage: CGImage)` (also `imageURL:`,
   `ciImage:`, `pixelBuffer:`) conforms to `PromptRepresentable`, so a multimodal
   prompt is just a `@PromptBuilder` closure: `{ Attachment(cg); text }`.

## App icon

The icon is generated from a vector source ([`AppIcon.svg`](AppIcon.svg)) — a chat
bubble with an AI "sparkle" on an indigo→violet gradient — rasterized to a flat,
opaque 1024×1024 PNG in the asset catalog.

## Not included

The **Spotlight-powered RAG search tool** (`SpotlightSearchTool` from the
`_CoreSpotlight_FoundationModels` overlay) is left out: it needs a CoreSpotlight
entitlement and on-device indexed content to return anything. It's a drop-in
`Tool` — add `SpotlightSearchTool(configuration:)` to a session's `tools:` if you
want it.
