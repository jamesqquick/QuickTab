import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let onSidebarChange: () -> Void
    @State private var selectedSection = SettingsSection.general
    @State private var launchError: String?

    var body: some View {
        HStack(spacing: 0) {
            navigation
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    sectionHeader
                    sectionContent
                }
                .padding(30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 760, height: 560)
        .onAppear(perform: refreshLaunchAtLoginStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLaunchAtLoginStatus()
        }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(QuickTabTheme.electric)
                    .frame(width: 34, height: 34)
                    .overlay(Image(systemName: "rectangle.2.swap").foregroundStyle(QuickTabTheme.ink))
                Text("QuickTab")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
            }
            .padding(.bottom, 18)

            ForEach(SettingsSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    Label(section.title, systemImage: section.icon)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .foregroundStyle(selectedSection == section ? QuickTabTheme.ink : QuickTabTheme.paper)
                        .background(selectedSection == section ? QuickTabTheme.electric : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("QUICKTAB 1.0")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(QuickTabTheme.paperMuted)
        }
        .padding(20)
        .frame(width: 210)
        .background(QuickTabTheme.ink)
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(selectedSection.title)
                .font(.system(size: 27, weight: .bold, design: .rounded))
            Text(selectedSection.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .general:
            SettingGroup(title: "Startup") {
                settingToggle("Launch QuickTab at login", isOn: launchBinding)
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
            }
            SettingGroup(title: "Window list") {
                visibilityPicker("Minimized windows", selection: $settings.minimizedVisibility)
                visibilityPicker("Hidden applications", selection: $settings.hiddenVisibility)
            }
            if !settings.excludedBundleIDs.isEmpty {
                SettingGroup(title: "Hidden from QuickTab") {
                    ForEach(settings.excludedBundleIDs.sorted(), id: \.self) { bundleIdentifier in
                        HStack {
                            Text(bundleIdentifier).font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Button("Show Again") { settings.excludedBundleIDs.remove(bundleIdentifier) }
                        }
                    }
                }
            }
        case .shortcuts:
            SettingGroup(title: "Switchers") {
                settingToggle("Replace Command-Tab", isOn: $settings.replaceCommandTab, detail: "Release Command to switch")
                settingToggle("Enable Option-Tab", isOn: $settings.enableOptionTab, detail: "A second recent-window switcher")
                settingToggle("Type to search while switching", isOn: $settings.directTyping)
            }
            SettingGroup(title: "Search") {
                shortcutRow("Window Search", keys: ["⌃", "space"])
                shortcutRow("Current App", keys: ["⌘", "`"])
                settingToggle("Enable Fast Search", isOn: $settings.enableFastSearch, detail: "Hold, type, release")
                Picker("Fast Search key", selection: $settings.fastSearchModifier) {
                    ForEach(FastSearchModifier.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!settings.enableFastSearch)
            }
        case .panel:
            SettingGroup(title: "Presentation") {
                settingToggle("Show switcher on every display", isOn: $settings.showOnAllDisplays)
                settingToggle("Select rows on pointer hover", isOn: $settings.hoverSelects)
            }
        case .sidebar:
            SettingGroup(title: "Edge sidebar") {
                settingToggle("Enable Sidebar", isOn: Binding(
                    get: { settings.sidebarEnabled },
                    set: { settings.sidebarEnabled = $0; onSidebarChange() }
                ))
                Picker("Screen edge", selection: Binding(
                    get: { settings.sidebarEdge },
                    set: { settings.sidebarEdge = $0; onSidebarChange() }
                )) {
                    ForEach(SidebarEdge.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Text("Move the pointer to the chosen display edge to reveal its window list.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .privacy:
            SettingGroup(title: "Private by design") {
                privacyRow(icon: "lock.shield", title: "On-device only", detail: "Window titles and search queries never leave your Mac.")
                privacyRow(icon: "chart.bar.xaxis", title: "No analytics", detail: "QuickTab contains no tracking or telemetry SDKs.")
                privacyRow(icon: "network.slash", title: "No network access", detail: "Core switching works without an internet connection.")
            }
        }
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    let status = settings.refreshLaunchAtLoginStatus()
                    if status == .requiresApproval {
                        launchError = "Approve QuickTab in System Settings > General > Login Items."
                    } else if settings.launchAtLogin != enabled {
                        launchError = "macOS did not update the Login Item. Check System Settings > General > Login Items."
                    } else {
                        launchError = nil
                    }
                } catch {
                    settings.refreshLaunchAtLoginStatus()
                    launchError = "Could not update Login Items: \(error.localizedDescription)"
                }
            }
        )
    }

    private func refreshLaunchAtLoginStatus() {
        let status = settings.refreshLaunchAtLoginStatus()
        launchError = status == .requiresApproval
            ? "Approve QuickTab in System Settings > General > Login Items."
            : nil
    }

    private func settingToggle(_ title: String, isOn: Binding<Bool>, detail: String? = nil) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .toggleStyle(.switch)
    }

    private func visibilityPicker(_ title: String, selection: Binding<ItemVisibility>) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            Picker(title, selection: selection) {
                ForEach(ItemVisibility.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)
        }
    }

    private func shortcutRow(_ title: String, keys: [String]) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            HStack(spacing: 4) { ForEach(keys, id: \.self) { key in Keycap(label: key) } }
        }
    }

    private func privacyRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(QuickTabTheme.electricDeep)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, shortcuts, panel, sidebar, privacy

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .general: "switch.2"
        case .shortcuts: "keyboard"
        case .panel: "rectangle.center.inset.filled"
        case .sidebar: "sidebar.right"
        case .privacy: "hand.raised"
        }
    }
    var subtitle: String {
        switch self {
        case .general: "Choose which windows appear and how QuickTab starts."
        case .shortcuts: "Move between windows without breaking your flow."
        case .panel: "Tune the centered switcher for your workspace."
        case .sidebar: "Keep every window one edge away."
        case .privacy: "Understand what QuickTab can see and where it stays."
        }
    }
}

private struct SettingGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            content
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
    }
}
