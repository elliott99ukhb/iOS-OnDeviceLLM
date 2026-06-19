import SwiftUI
import FoundationModels

/// Gates its content on the availability of the on-device system language model.
///
/// The model can be unavailable because the device isn't eligible for Apple
/// Intelligence, the user hasn't enabled it, or the model is still downloading.
/// We surface a readable explanation instead of failing silently.
struct ModelGate<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        switch SystemLanguageModel.default.availability {
        case .available:
            content()
        case .unavailable(let reason):
            ContentUnavailableView {
                Label("On-Device Model Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(
                    """
                    The on-device model isn't ready (\(String(describing: reason))).

                    • Make sure Apple Intelligence is turned on in Settings.
                    • On a fresh install the model may still be downloading — try again shortly.
                    • Use a device (or simulator) that supports Apple Intelligence.
                    """
                )
            }
            .padding()
        @unknown default:
            ContentUnavailableView(
                "On-Device Model Unavailable",
                systemImage: "exclamationmark.triangle"
            )
        }
    }
}
