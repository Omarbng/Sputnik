import SwiftUI

/// The HUD pill: the dock's material, 13 pt medium text, auto-dismissed by `HUDController`.
/// It springs in (a slight rise and scale) as it fades, instead of only fading.
struct HUDView: View {
    /// Transparent room around the pill for its shadow.
    static let shadowMargin: CGFloat = 40

    let message: String
    let style: HUDStyle
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false

    var body: some View {
        let tokens = Tokens.for(scheme)
        let reduce = Motion.reduceMotion
        HStack(spacing: 8) {
            Image(systemName: style == .error ? "exclamationmark.circle" : "checkmark.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(style == .error ? tokens.foreground : tokens.mutedForeground)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .tracking(-0.13)
                .foregroundStyle(tokens.foreground)
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(MaterialBackground(cornerRadius: nil))
        .scaleEffect(appeared || reduce ? 1 : 0.94)
        .offset(y: appeared || reduce ? 0 : 4)
        .padding(Self.shadowMargin)
        .fixedSize()
        .onAppear {
            withAnimation(.interpolatingSpring(mass: 0.5, stiffness: 520, damping: 28)) { appeared = true }
        }
    }
}
