import SwiftUI

/// Plain styling for now; section 5's look arrives in M5.
struct HUDView: View {
    let message: String
    let style: HUDStyle

    var body: some View {
        Label(message, systemImage: style == .error ? "exclamationmark.circle" : "checkmark.circle")
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            .padding(12)  // room for the shadow
            .fixedSize()
    }
}
