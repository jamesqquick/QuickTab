import SwiftUI

struct SidebarView: View {
    @ObservedObject var repository: WindowRepository
    @ObservedObject var settings: SettingsStore
    let screenID: CGDirectDisplayID?
    let edge: SidebarEdge

    private var windows: [WindowItem] {
        let onDisplay = repository.windows.filter { $0.screenID == screenID }
        return screenID == nil ? repository.windows : onDisplay
    }

    private var groupedWindows: [(String, [WindowItem])] {
        let groups = Dictionary(grouping: windows, by: \.appName)
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        HStack(spacing: 0) {
            if edge == .right { handle }
            content
            if edge == .left { handle }
        }
        .background(QuickTabTheme.ink)
        .clipShape(RoundedRectangle(cornerRadius: edge == .left ? 18 : 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.10)))
        .environment(\.colorScheme, .dark)
    }

    private var handle: some View {
        Rectangle()
            .fill(QuickTabTheme.electric)
            .frame(width: 6)
            .overlay(
                Capsule()
                    .fill(QuickTabTheme.ink.opacity(0.55))
                    .frame(width: 2, height: 42)
            )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "rectangle.2.swap")
                    .foregroundStyle(QuickTabTheme.electric)
                Text("QUICKTAB")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.8)
                Spacer()
                Text("\(windows.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(QuickTabTheme.paperMuted)
            }
            .foregroundStyle(QuickTabTheme.paper)
            .padding(.horizontal, 17)
            .padding(.vertical, 17)

            Divider().overlay(QuickTabTheme.divider)

            if windows.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "macwindow.badge.plus")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(QuickTabTheme.violet)
                    Text("Open a window to begin")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(QuickTabTheme.paperMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 15) {
                        ForEach(groupedWindows, id: \.0) { appName, items in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(appName.uppercased())
                                    Spacer()
                                    Text("\(items.count)")
                                }
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(1.4)
                                .foregroundStyle(QuickTabTheme.paperMuted)
                                .padding(.horizontal, 13)

                                ForEach(items) { item in
                                    Button {
                                        repository.activate(item)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(nsImage: item.icon)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 26, height: 26)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.title)
                                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                    .foregroundStyle(QuickTabTheme.paper)
                                                    .lineLimit(1)
                                                if item.isMinimized || item.isHidden {
                                                    Text(item.isMinimized ? "Minimized" : "Hidden")
                                                        .font(.system(size: 9, weight: .medium))
                                                        .foregroundStyle(item.isMinimized ? QuickTabTheme.coral : QuickTabTheme.violet)
                                                }
                                            }
                                            Spacer()
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(SidebarButtonStyle())
                                    .contextMenu {
                                        Button("Close Window") { repository.perform(.close, on: item) }
                                        Button("Minimize Window") { repository.perform(.minimize, on: item) }
                                        Button("Hide \(item.appName)") { repository.perform(.hideApplication, on: item) }
                                        Button("Quit \(item.appName)") { repository.perform(.quitApplication, on: item) }
                                        Divider()
                                        Button("Never Show \(item.appName)") {
                                            guard let bundleIdentifier = item.bundleIdentifier else { return }
                                            settings.excludedBundleIDs.insert(bundleIdentifier)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 13)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct SidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? QuickTabTheme.electric.opacity(0.16) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .padding(.horizontal, 6)
    }
}
