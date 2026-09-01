import AppKit
import SwiftUI

struct PermissionView: View {
    let requestPermission: () -> Void

    var body: some View {
        ZStack {
            QuickTabTheme.panelGradient.ignoresSafeArea()
            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(QuickTabTheme.electric)
                        .frame(width: 82, height: 82)
                    Image(systemName: "rectangle.2.swap")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(QuickTabTheme.ink)
                }
                VStack(spacing: 9) {
                    Text("Meet QuickTab")
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .foregroundStyle(QuickTabTheme.paper)
                    Text("Every window, two keystrokes away.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(QuickTabTheme.paperMuted)
                }
                VStack(alignment: .leading, spacing: 13) {
                    permissionLine(icon: "keyboard", text: "Press Control-Space to search")
                    permissionLine(icon: "command", text: "Use Command-Tab for individual windows")
                    permissionLine(icon: "lock.shield", text: "Everything stays on this Mac")
                }
                .padding(18)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

                Button(action: requestPermission) {
                    Text("Allow Accessibility Access")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(QuickTabTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(QuickTabTheme.electric, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                Text("QuickTab needs permission to read window titles and bring the selected window forward.")
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(QuickTabTheme.paperMuted)
                    .frame(maxWidth: 350)
            }
            .padding(40)
        }
        .frame(width: 500, height: 590)
        .environment(\.colorScheme, .dark)
    }

    private func permissionLine(icon: String, text: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .foregroundStyle(QuickTabTheme.electric)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(QuickTabTheme.paper)
        }
    }
}
