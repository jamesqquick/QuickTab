import Foundation
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let replaceCommandTab = "replaceCommandTab"
        static let enableOptionTab = "enableOptionTab"
        static let enableFastSearch = "enableFastSearch"
        static let fastSearchModifier = "fastSearchModifier"
        static let showOnAllDisplays = "showOnAllDisplays"
        static let hoverSelects = "hoverSelects"
        static let minimizedVisibility = "minimizedVisibility"
        static let hiddenVisibility = "hiddenVisibility"
        static let excludedBundleIDs = "excludedBundleIDs"
    }

    private let defaults: UserDefaults

    @Published var replaceCommandTab: Bool { didSet { save() } }
    @Published var enableOptionTab: Bool { didSet { save() } }
    @Published var enableFastSearch: Bool { didSet { save() } }
    @Published var fastSearchModifier: FastSearchModifier { didSet { save() } }
    @Published var showOnAllDisplays: Bool { didSet { save() } }
    @Published var hoverSelects: Bool { didSet { save() } }
    @Published var minimizedVisibility: ItemVisibility { didSet { save() } }
    @Published var hiddenVisibility: ItemVisibility { didSet { save() } }
    @Published var excludedBundleIDs: Set<String> { didSet { save() } }
    @Published var launchAtLogin: Bool { didSet { save() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.replaceCommandTab: true,
            Key.enableOptionTab: false,
            Key.enableFastSearch: true,
            Key.fastSearchModifier: FastSearchModifier.rightOption.rawValue,
            Key.showOnAllDisplays: true,
            Key.hoverSelects: true,
            Key.minimizedVisibility: ItemVisibility.bottom.rawValue,
            Key.hiddenVisibility: ItemVisibility.bottom.rawValue,
        ])

        replaceCommandTab = defaults.bool(forKey: Key.replaceCommandTab)
        enableOptionTab = defaults.bool(forKey: Key.enableOptionTab)
        enableFastSearch = defaults.bool(forKey: Key.enableFastSearch)
        fastSearchModifier = FastSearchModifier(rawValue: defaults.string(forKey: Key.fastSearchModifier) ?? "rightOption") ?? .rightOption
        showOnAllDisplays = defaults.bool(forKey: Key.showOnAllDisplays)
        hoverSelects = defaults.bool(forKey: Key.hoverSelects)
        minimizedVisibility = ItemVisibility(rawValue: defaults.string(forKey: Key.minimizedVisibility) ?? "bottom") ?? .bottom
        hiddenVisibility = ItemVisibility(rawValue: defaults.string(forKey: Key.hiddenVisibility) ?? "bottom") ?? .bottom
        excludedBundleIDs = Set(defaults.stringArray(forKey: Key.excludedBundleIDs) ?? [])
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    func refreshLaunchAtLoginStatus() -> SMAppService.Status {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        return status
    }

    private func save() {
        defaults.set(replaceCommandTab, forKey: Key.replaceCommandTab)
        defaults.set(enableOptionTab, forKey: Key.enableOptionTab)
        defaults.set(enableFastSearch, forKey: Key.enableFastSearch)
        defaults.set(fastSearchModifier.rawValue, forKey: Key.fastSearchModifier)
        defaults.set(showOnAllDisplays, forKey: Key.showOnAllDisplays)
        defaults.set(hoverSelects, forKey: Key.hoverSelects)
        defaults.set(minimizedVisibility.rawValue, forKey: Key.minimizedVisibility)
        defaults.set(hiddenVisibility.rawValue, forKey: Key.hiddenVisibility)
        defaults.set(Array(excludedBundleIDs), forKey: Key.excludedBundleIDs)
    }
}
