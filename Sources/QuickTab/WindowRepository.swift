import AppKit
import ApplicationServices
import Combine
import OSLog

private let windowInteractionQueue = DispatchQueue(
    label: "com.jamesqquick.QuickTab.window-interactions",
    qos: .userInitiated
)

private final class WindowInteractionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }

    func canContinue() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isCancelled
    }
}

private let accessibilityMessagingTimeoutConfigured: Void = {
    let systemWideElement = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(systemWideElement, 0.5)
}()

private extension Logger {
    static let windowInteraction = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.jamesqquick.QuickTab",
        category: "WindowInteraction"
    )
}

@MainActor
protocol WindowRepositoryProtocol: AnyObject {
    var windowsPublisher: AnyPublisher<[WindowItem], Never> { get }
    var activeWindowID: WindowID? { get }

    func activate(_ item: WindowItem) async
    func perform(_ action: WindowAction, on item: WindowItem) async -> Bool
}

@MainActor
final class WindowRepository: ObservableObject, WindowRepositoryProtocol {
    @Published private(set) var windows: [WindowItem] = []
    @Published private(set) var hasAccessibilityPermission = AXIsProcessTrusted()
    @Published private(set) var activeWindowID: WindowID?

    private var lastActive: [WindowID: Date] = [:]
    private var refreshTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var activeWindowLookupTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var isRefreshing = false
    private var refreshPending = false
    private var scheduledRefresh: DispatchWorkItem?
    private var refreshNotBefore = Date.distantPast
    private var contextCache: [WindowID: String] = [:]
    private var itemCache: [pid_t: [WindowItem]] = [:]
    private var scanRotation = 0
    private var suppressedWindows: [WindowID: Date] = [:]
    private var suppressedProcesses: [pid_t: Date] = [:]
    private var currentPreferences = VisibilityPreferences(
        minimized: .bottom,
        hidden: .bottom,
        excludedBundleIDs: []
    )

    init() {
        _ = accessibilityMessagingTimeoutConfigured
    }

    var windowsPublisher: AnyPublisher<[WindowItem], Never> {
        $windows.eraseToAnyPublisher()
    }

    func start(preferences: @escaping @MainActor () -> VisibilityPreferences) {
        stop()
        refresh(preferences: preferences())
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refresh(preferences: preferences())
            }
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                else { return }
                self.activeWindowLookupTask?.cancel()
                let processID = app.processIdentifier
                self.activeWindowLookupTask = Task { [weak self] in
                    let lookup = await Self.focusedWindowLookup(processID: processID)
                    guard !Task.isCancelled, let self else { return }
                    self.activeWindowLookupTask = nil
                    self.markActiveWindow(processID: processID, lookup: lookup)
                    self.refresh(preferences: preferences())
                }
            }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        scheduledRefresh?.cancel()
        scheduledRefresh = nil
        activeWindowLookupTask?.cancel()
        activeWindowLookupTask = nil
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        workspaceObserver = nil
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
    }

    func refresh(preferences: VisibilityPreferences) {
        currentPreferences = preferences
        hasAccessibilityPermission = AXIsProcessTrusted()
        let delay = refreshNotBefore.timeIntervalSinceNow
        if delay > 0 {
            refreshPending = true
            scheduleRefresh(after: delay)
            return
        }
        guard !isRefreshing else {
            refreshPending = true
            return
        }

        isRefreshing = true
        refreshPending = false
        refreshGeneration += 1
        let generation = refreshGeneration
        let history = lastActive
        let cachedContexts = contextCache
        let cachedItems = itemCache
        let previousActiveWindowID = activeWindowID
        let rotation = scanRotation
        scanRotation &+= 1
        let now = Date()
        suppressedWindows = suppressedWindows.filter { $0.value > now }
        suppressedProcesses = suppressedProcesses.filter { $0.value > now }
        let suppressedWindows = suppressedWindows
        let suppressedProcesses = suppressedProcesses

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let collection = Self.collectWindows(
                preferences: preferences,
                history: history,
                cachedContexts: cachedContexts,
                cachedItems: cachedItems,
                previousActiveWindowID: previousActiveWindowID,
                rotation: rotation,
                suppressedWindows: suppressedWindows,
                suppressedProcesses: suppressedProcesses
            )
            DispatchQueue.main.async {
                guard let self else { return }
                if generation == self.refreshGeneration {
                    self.windows = collection.items
                    self.activeWindowID = collection.activeWindowID
                    self.contextCache = collection.contexts
                    self.itemCache = collection.snapshots
                    if let activeWindowID = collection.activeWindowID {
                        self.lastActive[activeWindowID] = Date()
                    }
                }
                self.isRefreshing = false
                if self.refreshPending {
                    self.refreshPending = false
                    self.refresh(preferences: self.currentPreferences)
                }
            }
        }
    }

    func activate(_ item: WindowItem) async {
        let windowActivated = await Self.activateWindow(item)
        guard !Task.isCancelled, windowActivated else { return }
        refreshGeneration += 1
        let now = Date()
        lastActive[item.id] = now
        activeWindowID = item.id
        promote(item.id, at: now)
    }

    @discardableResult
    func perform(_ action: WindowAction, on item: WindowItem) async -> Bool {
        let execution = await Self.performWindowAction(action, on: item)
        guard case let .completed(reportedSuccess) = execution else { return false }
        guard action.isAccepted(reportedSuccess: reportedSuccess) else { return false }

        switch action {
        case .close:
            suppressedWindows[item.id] = Date().addingTimeInterval(4)
            windows.removeAll { $0.id == item.id }
            itemCache[item.processID]?.removeAll { $0.id == item.id }
            contextCache.removeValue(forKey: item.id)
            lastActive.removeValue(forKey: item.id)
        case .quitApplication:
            suppressedProcesses[item.processID] = Date().addingTimeInterval(8)
            windows.removeAll { $0.processID == item.processID }
            itemCache.removeValue(forKey: item.processID)
            contextCache = contextCache.filter { $0.key.processID != item.processID }
            lastActive = lastActive.filter { $0.key.processID != item.processID }
        case .minimize, .hideApplication:
            break
        }
        if action == .close || action == .quitApplication {
            refreshGeneration += 1
            refreshNotBefore = Date().addingTimeInterval(0.35)
        }
        refreshAfterAction()
        return true
    }

    nonisolated private static func activateWindow(_ item: WindowItem) async -> Bool {
        await runWindowInteraction("activate", processID: item.processID) { cancellation in
            activateWindowSynchronously(item, cancellation: cancellation)
        } ?? false
    }

    nonisolated private static func activateWindowSynchronously(
        _ item: WindowItem,
        cancellation: WindowInteractionCancellation
    ) -> Bool {
        guard cancellation.canContinue() else { return false }
        guard let app = NSRunningApplication(processIdentifier: item.processID) else { return false }
        app.unhide()
        guard cancellation.canContinue() else { return false }
        guard app.activate(options: []) else { return false }
        guard cancellation.canContinue() else { return false }
        guard let element = item.element else { return true }

        if item.isMinimized {
            _ = AXUIElementSetAttributeValue(
                element,
                kAXMinimizedAttribute as CFString,
                kCFBooleanFalse
            )
            guard cancellation.canContinue() else { return false }
        }
        let appElement = AXUIElementCreateApplication(item.processID)
        let raised = AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success
        guard cancellation.canContinue() else { return false }
        _ = AXUIElementSetAttributeValue(
            appElement,
            kAXMainWindowAttribute as CFString,
            element
        )
        guard cancellation.canContinue() else { return false }
        _ = AXUIElementSetAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            element
        )
        return raised
    }

    nonisolated private static func performWindowAction(
        _ action: WindowAction,
        on item: WindowItem
    ) async -> WindowActionExecution {
        await runWindowInteraction(String(describing: action), processID: item.processID) { cancellation in
            performWindowActionSynchronously(action, on: item, cancellation: cancellation)
        } ?? .cancelled
    }

    private enum WindowActionExecution: Sendable {
        case cancelled
        case completed(Bool)
    }

    nonisolated private static func performWindowActionSynchronously(
        _ action: WindowAction,
        on item: WindowItem,
        cancellation: WindowInteractionCancellation
    ) -> WindowActionExecution {
        guard cancellation.canContinue() else { return .cancelled }
        switch action {
        case .close:
            guard let element = item.element,
                  let button: AXUIElement = axValue(element, kAXCloseButtonAttribute) else {
                return .completed(false)
            }
            guard cancellation.canContinue() else { return .cancelled }
            return .completed(AXUIElementPerformAction(button, kAXPressAction as CFString) == .success)
        case .minimize:
            guard NSRunningApplication(processIdentifier: item.processID) != nil,
                  let element = item.element else { return .completed(false) }
            guard cancellation.canContinue() else { return .cancelled }
            return .completed(AXUIElementSetAttributeValue(
                element,
                kAXMinimizedAttribute as CFString,
                kCFBooleanTrue
            ) == .success)
        case .hideApplication:
            return .completed(NSRunningApplication(processIdentifier: item.processID)?.hide() == true)
        case .quitApplication:
            return .completed(NSRunningApplication(processIdentifier: item.processID)?.terminate() == true)
        }
    }

    nonisolated private static func logSlowInteraction(
        _ operation: String,
        processID: pid_t,
        startedAt: ContinuousClock.Instant
    ) {
        let duration = startedAt.duration(to: .now)
        guard duration >= .milliseconds(100) else { return }
        Logger.windowInteraction.warning(
            "Slow window interaction: \(operation, privacy: .public), pid=\(processID), duration=\(String(describing: duration), privacy: .public)"
        )
    }

    private struct FocusedWindowLookup: Sendable {
        let succeeded: Bool
        let fingerprint: String?
    }

    nonisolated private static func focusedWindowLookup(processID: pid_t) async -> FocusedWindowLookup {
        await runWindowInteraction("focused-window lookup", processID: processID) { _ in
            let appElement = AXUIElementCreateApplication(processID)
            AXUIElementSetMessagingTimeout(appElement, 0.05)
            var focusedValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedWindowAttribute as CFString,
                &focusedValue
            ) == .success else {
                return FocusedWindowLookup(succeeded: false, fingerprint: nil)
            }
            guard let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
                return FocusedWindowLookup(succeeded: true, fingerprint: nil)
            }
            let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)
            return FocusedWindowLookup(succeeded: true, fingerprint: String(CFHash(focused)))
        } ?? FocusedWindowLookup(succeeded: false, fingerprint: nil)
    }

    nonisolated private static func runWindowInteraction<Result: Sendable>(
        _ operation: String,
        processID: pid_t,
        work: @escaping @Sendable (WindowInteractionCancellation) -> Result
    ) async -> Result? {
        let cancellation = WindowInteractionCancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                windowInteractionQueue.async {
                    guard cancellation.canContinue() else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let startedAt = ContinuousClock.now
                    let result = work(cancellation)
                    logSlowInteraction(operation, processID: processID, startedAt: startedAt)
                    continuation.resume(returning: result)
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func markActiveWindow(processID: pid_t, lookup: FocusedWindowLookup) {
        guard lookup.succeeded else { return }
        let now = Date()

        if let fingerprint = lookup.fingerprint {
            if let item = windows.first(where: { $0.processID == processID && $0.id.fingerprint == fingerprint }) {
                lastActive[item.id] = now
                activeWindowID = item.id
                promote(item.id, at: now)
            }
            return
        }

        let appItems = windows.filter { $0.processID == processID }
        if appItems.count == 1, let item = appItems.first {
            lastActive[item.id] = now
            activeWindowID = item.id
            promote(item.id, at: now)
        }
    }

    private func promote(_ id: WindowID, at date: Date) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        let item = windows.remove(at: index).updatingLastActive(date)
        windows.insert(item, at: 0)
    }

    private func refreshAfterAction() {
        scheduleRefresh(after: max(0, refreshNotBefore.timeIntervalSinceNow))
    }

    private func scheduleRefresh(after delay: TimeInterval) {
        scheduledRefresh?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.scheduledRefresh = nil
            self.refresh(preferences: self.currentPreferences)
        }
        scheduledRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    nonisolated private static func collectWindows(
        preferences: VisibilityPreferences,
        history: [WindowID: Date],
        cachedContexts: [WindowID: String],
        cachedItems: [pid_t: [WindowItem]],
        previousActiveWindowID: WindowID?,
        rotation: Int,
        suppressedWindows: [WindowID: Date],
        suppressedProcesses: [pid_t: Date]
    ) -> (
        items: [WindowItem],
        activeWindowID: WindowID?,
        contexts: [WindowID: String],
        snapshots: [pid_t: [WindowItem]]
    ) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != ownPID &&
                $0.activationPolicy == .regular &&
                !preferences.excludedBundleIDs.contains($0.bundleIdentifier ?? "")
        }
        let frontmostApp = apps.first { $0.processIdentifier == frontmostPID }
        let remainingApps = apps.filter { $0.processIdentifier != frontmostPID }
        let rotationIndex = remainingApps.isEmpty ? 0 : rotation % remainingApps.count
        let rotatedApps = Array(remainingApps[rotationIndex...]) + Array(remainingApps[..<rotationIndex])
        let orderedApps = [frontmostApp].compactMap { $0 } + rotatedApps
        var items: [WindowItem] = []
        var activeWindowID: WindowID?
        var contexts: [WindowID: String] = [:]
        let scanDeadline = Date().addingTimeInterval(1.5)

        for app in orderedApps {
            let cachedAppItems = cachedItems[app.processIdentifier] ?? []
            guard Date() < scanDeadline else {
                items.append(contentsOf: cachedAppItems)
                if app.processIdentifier == frontmostPID,
                   let previousActiveWindowID,
                   cachedAppItems.contains(where: { $0.id == previousActiveWindowID }) {
                    activeWindowID = previousActiveWindowID
                }
                for item in cachedAppItems {
                    if let context = item.context { contexts[item.id] = context }
                }
                continue
            }

            let appDeadline = min(scanDeadline, Date().addingTimeInterval(0.45))
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.12)
            let appName = displayName(for: app)
            let appWindows: [AXUIElement] = axValue(appElement, kAXWindowsAttribute, before: appDeadline) ?? []
            let focusedWindow: AXUIElement? = app.processIdentifier == frontmostPID
                ? axValue(appElement, kAXFocusedWindowAttribute, before: appDeadline)
                : nil
            let focusedElement: AXUIElement? = app.processIdentifier == frontmostPID
                ? axValue(appElement, kAXFocusedUIElementAttribute, before: appDeadline)
                : nil
            let focusedHash = focusedWindow.map(CFHash)
            var appItems: [WindowItem] = []
            var timedOut = Date() >= appDeadline

            for element in appWindows {
                guard Date() < appDeadline else {
                    timedOut = true
                    break
                }
                let role: String = axValue(element, kAXRoleAttribute, before: appDeadline) ?? ""
                let subrole: String = axValue(element, kAXSubroleAttribute, before: appDeadline) ?? ""
                let rawTitle: String = axValue(element, kAXTitleAttribute, before: appDeadline) ?? ""
                guard role == (kAXWindowRole as String) else { continue }
                guard subrole != (kAXSystemDialogSubrole as String) else { continue }
                guard subrole != (kAXUnknownSubrole as String) || !rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                let document: String = axValue(element, kAXDocumentAttribute, before: appDeadline) ?? ""
                let description: String = axValue(element, kAXDescriptionAttribute, before: appDeadline) ?? ""
                guard Date() < appDeadline else {
                    timedOut = true
                    break
                }
                let title = displayTitle(
                    title: rawTitle,
                    document: document,
                    description: description,
                    appName: appName
                )
                let isMinimized: Bool = axValue(element, kAXMinimizedAttribute, before: appDeadline) ?? false

                let frame = axFrame(element, before: appDeadline)
                let midpoint = frame.map { CGPoint(x: $0.midX, y: $0.midY) }
                let screenID = midpoint.flatMap(displayID(containing:))
                let fingerprint = String(CFHash(element))
                let id = WindowID(processID: app.processIdentifier, fingerprint: fingerprint)
                let isFocused = focusedHash == CFHash(element)
                let context: String?
                if !document.isEmpty {
                    context = WindowMetadata.contextLabel(document, title: title)
                } else if app.bundleIdentifier?.hasPrefix("com.google.Chrome") == true {
                    if isFocused || cachedContexts[id] == nil {
                        let rawURL = chromeTabURL(
                            in: element,
                            focusedElement: isFocused ? focusedElement : nil,
                            before: appDeadline
                        )
                        context = rawURL.flatMap { WindowMetadata.contextLabel($0, title: title) }
                            ?? cachedContexts[id]
                    } else {
                        context = cachedContexts[id]
                    }
                } else {
                    context = WindowMetadata.contextLabel(description, title: title)
                }
                guard Date() < appDeadline else {
                    timedOut = true
                    break
                }
                if let context { contexts[id] = context }
                if isFocused { activeWindowID = id }

                appItems.append(WindowItem(
                    id: id,
                    processID: app.processIdentifier,
                    appName: appName,
                    bundleIdentifier: app.bundleIdentifier,
                    title: title,
                    context: context,
                    icon: app.icon ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil) ?? NSImage(),
                    element: element,
                    frame: frame,
                    screenID: screenID,
                    isMinimized: isMinimized,
                    isHidden: app.isHidden,
                    lastActive: isFocused ? Date() : history[id] ?? app.launchDate ?? .distantPast
                ))
            }

            appItems = WindowReconciler.merge(fresh: appItems, cached: cachedAppItems) { item in
                timedOut || cachedWindowIsAlive(item, before: appDeadline)
            }
            for item in appItems {
                if let context = item.context { contexts[item.id] = context }
            }
            if app.processIdentifier == frontmostPID,
               activeWindowID == nil,
               let previousActiveWindowID,
               appItems.contains(where: { $0.id == previousActiveWindowID }) {
                activeWindowID = previousActiveWindowID
            }
            items.append(contentsOf: appItems)
        }

        let now = Date()
        let unsuppressedItems = items.filter { item in
            suppressedWindows[item.id, default: .distantPast] <= now &&
                suppressedProcesses[item.processID, default: .distantPast] <= now
        }
        let visibleIDs = Set(unsuppressedItems.map(\.id))
        contexts = contexts.filter { visibleIDs.contains($0.key) }
        let visibleActiveWindowID = activeWindowID.flatMap { visibleIDs.contains($0) ? $0 : nil }
        let snapshots = Dictionary(grouping: unsuppressedItems, by: \.processID)
        let sortedItems = unsuppressedItems
            .filter { item in visibility(for: item, preferences: preferences) != .hide }
            .sorted { lhs, rhs in
                let lhsVisibility = visibility(for: lhs, preferences: preferences)
                let rhsVisibility = visibility(for: rhs, preferences: preferences)
                if lhsVisibility != rhsVisibility { return lhsVisibility == .show }
                if lhs.lastActive != rhs.lastActive { return lhs.lastActive > rhs.lastActive }
                if lhs.appName != rhs.appName { return lhs.appName.localizedStandardCompare(rhs.appName) == .orderedAscending }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        return (sortedItems, visibleActiveWindowID, contexts, snapshots)
    }

    nonisolated private static func visibility(
        for item: WindowItem,
        preferences: VisibilityPreferences
    ) -> ItemVisibility {
        if item.isMinimized { return preferences.minimized }
        if item.isHidden { return preferences.hidden }
        return .show
    }

    nonisolated private static func axFrame(_ element: AXUIElement, before deadline: Date) -> CGRect? {
        guard
            let positionValue: AXValue = axValue(element, kAXPositionAttribute, before: deadline),
            let sizeValue: AXValue = axValue(element, kAXSizeAttribute, before: deadline)
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position), AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    nonisolated private static func cachedWindowIsAlive(_ item: WindowItem, before deadline: Date) -> Bool {
        guard let element = item.element else { return false }
        guard Date() < deadline else { return true }

        var roleValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        if error == .invalidUIElement { return false }
        guard error == .success else { return true }
        return roleValue as? String == (kAXWindowRole as String)
    }

    nonisolated private static func displayID(containing point: CGPoint) -> CGDirectDisplayID? {
        var displayID = CGDirectDisplayID()
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &displayID, &count) == .success, count > 0 else { return nil }
        return displayID
    }

    nonisolated private static func displayTitle(
        title: String,
        document: String,
        description: String,
        appName: String
    ) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        if let url = URL(string: document), !url.lastPathComponent.isEmpty { return url.lastPathComponent }
        let documentName = (document as NSString).lastPathComponent
        if !documentName.isEmpty { return documentName }
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? "\(appName) Window" : description
    }

    nonisolated private static func chromeTabURL(
        in window: AXUIElement,
        focusedElement: AXUIElement?,
        before deadline: Date
    ) -> String? {
        if let focusedElement {
            var current: AXUIElement? = focusedElement
            var visited: Set<CFHashCode> = []
            for _ in 0..<12 {
                guard Date() < deadline, let element = current else { break }
                guard visited.insert(CFHash(element)).inserted else { break }
                let role: String = axValue(element, kAXRoleAttribute, before: deadline) ?? ""
                if role == "AXWebArea", let url = attributeString(element, kAXURLAttribute as String, before: deadline) {
                    return url
                }
                current = axValue(element, kAXParentAttribute, before: deadline)
            }
        }

        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var visited: Set<CFHashCode> = []
        var inspected = 0

        while !queue.isEmpty, inspected < 120, Date() < deadline {
            let (element, depth) = queue.removeFirst()
            let hash = CFHash(element)
            guard visited.insert(hash).inserted else { continue }
            inspected += 1

            let role: String = axValue(element, kAXRoleAttribute, before: deadline) ?? ""
            if role == "AXWebArea", let url = attributeString(element, kAXURLAttribute as String, before: deadline) {
                return url
            }
            guard depth < 8, role != "AXWebArea" else { continue }
            let focused: AXUIElement? = axValue(element, kAXFocusedUIElementAttribute, before: deadline)
            let selected: [AXUIElement] = axValue(element, kAXSelectedChildrenAttribute, before: deadline) ?? []
            let children: [AXUIElement] = axValue(element, kAXChildrenAttribute, before: deadline) ?? []
            let prioritized = [focused].compactMap { $0 } + selected
            queue.insert(contentsOf: prioritized.map { ($0, depth + 1) }, at: 0)
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
        return nil
    }

    nonisolated private static func displayName(for app: NSRunningApplication) -> String {
        if let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let bundleName = app.bundleURL?.deletingPathExtension().lastPathComponent, !bundleName.isEmpty {
            return bundleName
        }
        if let executableName = app.executableURL?.lastPathComponent, !executableName.isEmpty {
            return executableName
        }
        return app.bundleIdentifier ?? "Process \(app.processIdentifier)"
    }

    nonisolated private static func attributeString(
        _ element: AXUIElement,
        _ attribute: String,
        before deadline: Date
    ) -> String? {
        guard Date() < deadline else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        if let string = value as? String { return string }
        if let url = value as? URL { return url.absoluteString }
        return nil
    }

    nonisolated private static func axValue<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    nonisolated private static func axValue<T>(
        _ element: AXUIElement,
        _ attribute: String,
        before deadline: Date
    ) -> T? {
        guard Date() < deadline else { return nil }
        return axValue(element, attribute)
    }
}
