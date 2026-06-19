import SwiftUI

/// The app is a focused, on-device chat client. Everything is gated behind
/// `ModelGate`, which shows a friendly message if the on-device model isn't
/// available on this device/simulator.
struct ContentView: View {
    var body: some View {
        ModelGate {
            ChatView()
        }
    }
}

#Preview {
    ContentView()
}
