import SwiftUI

enum QuickTabTheme {
    static let ink = Color(red: 0.11, green: 0.09, blue: 0.17)
    static let inkRaised = Color(red: 0.16, green: 0.13, blue: 0.23)
    static let paper = Color(red: 0.96, green: 0.95, blue: 0.99)
    static let paperMuted = Color(red: 0.77, green: 0.75, blue: 0.84)
    static let electric = Color(red: 0.43, green: 0.91, blue: 0.84)
    static let electricDeep = Color(red: 0.18, green: 0.60, blue: 0.57)
    static let coral = Color(red: 1.00, green: 0.47, blue: 0.42)
    static let violet = Color(red: 0.56, green: 0.43, blue: 0.92)
    static let divider = Color.white.opacity(0.10)

    static let panelGradient = LinearGradient(
        colors: [inkRaised, ink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct Keycap: View {
    let label: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(colorScheme == .dark ? QuickTabTheme.paperMuted : QuickTabTheme.inkRaised)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                colorScheme == .dark ? Color.white.opacity(0.08) : QuickTabTheme.ink.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.10) : QuickTabTheme.ink.opacity(0.10))
            )
    }
}
