import AppKit
import ApplicationServices

struct WindowID: Hashable, Codable, CustomStringConvertible, Sendable {
    let processID: pid_t
    let fingerprint: String

    var description: String { "\(processID):\(fingerprint)" }
}

// Window snapshots cross the scan queue; their AppKit and AX references are read-only there.
struct WindowItem: Identifiable, Hashable, @unchecked Sendable {
    let id: WindowID
    let processID: pid_t
    let appName: String
    let bundleIdentifier: String?
    let title: String
    let context: String?
    let icon: NSImage
    let element: AXUIElement?
    let frame: CGRect?
    let screenID: CGDirectDisplayID?
    let isMinimized: Bool
    let isHidden: Bool
    let lastActive: Date

    var searchIdentity: String {
        "\(bundleIdentifier ?? appName)|\(title)"
    }

    var subtitle: String {
        guard let context else { return appName }
        return "\(appName)  ·  \(context)"
    }

    static func == (lhs: WindowItem, rhs: WindowItem) -> Bool {
        lhs.id == rhs.id && lhs.isMinimized == rhs.isMinimized && lhs.isHidden == rhs.isHidden
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(isMinimized)
        hasher.combine(isHidden)
    }

    func updatingLastActive(_ date: Date) -> WindowItem {
        WindowItem(
            id: id,
            processID: processID,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            title: title,
            context: context,
            icon: icon,
            element: element,
            frame: frame,
            screenID: screenID,
            isMinimized: isMinimized,
            isHidden: isHidden,
            lastActive: date
        )
    }
}

enum WindowReconciler {
    static func merge(
        fresh: [WindowItem],
        cached: [WindowItem],
        shouldRetainCached: (WindowItem) -> Bool
    ) -> [WindowItem] {
        var seen: Set<WindowID> = []
        var result: [WindowItem] = []

        for item in fresh where seen.insert(item.id).inserted {
            result.append(item)
        }
        for item in cached where !seen.contains(item.id) && shouldRetainCached(item) {
            seen.insert(item.id)
            result.append(item)
        }
        return result
    }
}

enum WindowAction: Equatable {
    case close
    case minimize
    case hideApplication
    case quitApplication
}

enum WindowMetadata {
    static func contextLabel(_ rawValue: String, title: String) -> String? {
        let rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty, rawValue.caseInsensitiveCompare(title) != .orderedSame else { return nil }

        if let url = URL(string: rawValue), let scheme = url.scheme?.lowercased() {
            if scheme == "http" || scheme == "https" {
                guard let host = url.host else { return rawValue }
                let normalizedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
                let path = url.path.removingPercentEncoding ?? url.path
                return path.isEmpty || path == "/" ? normalizedHost : normalizedHost + path
            }
            if scheme == "file" {
                return compactPath(url.path)
            }
        }

        if rawValue.hasPrefix("/") { return compactPath(rawValue) }
        let genericDescriptions = ["window", "standard window", "application"]
        return genericDescriptions.contains(rawValue.lowercased()) ? nil : rawValue
    }

    private static func compactPath(_ path: String) -> String {
        let components = (path as NSString).pathComponents.filter { $0 != "/" }
        return components.suffix(2).joined(separator: "/")
    }
}

enum ItemVisibility: String, CaseIterable, Codable, Identifiable {
    case show
    case bottom
    case hide

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum SidebarEdge: String, CaseIterable, Codable, Identifiable {
    case left
    case right

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum FastSearchModifier: String, CaseIterable, Codable, Identifiable {
    case rightOption
    case leftOption
    case function

    var id: String { rawValue }
    var label: String {
        switch self {
        case .rightOption: "Right Option"
        case .leftOption: "Left Option"
        case .function: "Function (Fn)"
        }
    }
}

enum SwitcherMode: Equatable {
    case recent
    case application(pid_t)
    case search
    case fastSearch
}

struct SearchResult: Identifiable {
    let item: WindowItem
    let score: Double
    let matchedTitleIndices: IndexSet
    let matchedAppIndices: IndexSet

    var id: WindowID { item.id }
}

struct VisibilityPreferences {
    let minimized: ItemVisibility
    let hidden: ItemVisibility
    let excludedBundleIDs: Set<String>
}
