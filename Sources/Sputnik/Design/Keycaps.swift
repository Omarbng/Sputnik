import SwiftUI

/// Small shortcut chips, like the tooltip's but on the normal surface: 18 pt squares with a
/// 1 px border at 30% opacity.
struct Keycaps: View {
    let keys: [String]
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 11, weight: .medium))
                    .frame(minWidth: 18, minHeight: 18)
                    .padding(.horizontal, key.count > 1 ? 4 : 0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(color.opacity(0.3), lineWidth: 1)
                    )
            }
        }
        .foregroundStyle(color)
    }
}
