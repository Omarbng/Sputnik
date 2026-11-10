import SwiftUI

/// The HUD pill: the dock's material, 13 pt medium text, auto-dismissed by `HUDController`.
struct HUDView: View {
    /// Transparent room around the pill for its shadow.
    static let shadowMargin: CGFloat = 32

    let message: String
    let style: HUDStyle
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = Tokens.for(scheme)
        HStack(spacing: 8) {
            Image(systemName: style == .error ? "exclamationmark.circle" : "checkmark.circle")
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .tracking(-0.13)
        }
        .foregroundStyle(tokens.foreground)
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(MaterialBackground(cornerRadius: nil))
        .padding(Self.shadowMargin)
        .fixedSize()
    }
}
