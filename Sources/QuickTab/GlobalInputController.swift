import AppKit
import CoreGraphics

struct GlobalInputConfiguration {
    var replaceCommandTab = true
    var enableOptionTab = false
    var enableFastSearch = true
    var fastSearchModifier = FastSearchModifier.rightOption
    var directTyping = true
}

@MainActor
protocol GlobalInputHandler: AnyObject {
    var isSwitcherVisible: Bool { get }
    func presentSwitcher(mode: SwitcherMode, advanceImmediately: Bool)
    func moveSwitcherSelection(by offset: Int)
    func appendSwitcherQuery(_ text: String)
    func beginSwitcherSearch()
    func deleteSwitcherQueryCharacter()
    func commitSwitcherSelection()
    func dismissSwitcher()
    func performSwitcherAction(_ action: WindowAction)
    func pointerMoved(to point: CGPoint)
    func pointerPressed(at point: CGPoint)
    func edgeScrolled(delta: Double)
    func inputSessionDidReset()
}

final class GlobalInputController {
    weak var handler: GlobalInputHandler?
    var configuration = GlobalInputConfiguration() {
        didSet { resetActiveSwitcherSession(notifyHandler: true) }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var cyclingModifier: CGEventFlags?
    private var fastModifierHeld = false
    private var fastSearchActive = false
    private var pendingMousePoint: CGPoint?
    private var mouseUpdateScheduled = false
    private var edgeScrollAccumulator = 0.0
    private var edgeGestureRecognized = false
    private var lastEdgeScrollAt = Date.distantPast
    private var presentationPending = false
    private var endingActionKeyCode: UInt16?
    private let mouseLocation: () -> CGPoint
    private let outerDisplayEdgePredicate: (CGPoint) -> Bool
    private let modifierKeyState: (CGKeyCode) -> Bool

    var isInstalled: Bool { eventTap != nil }

    init(
        mouseLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation },
        isAtOuterDisplayEdge: ((CGPoint) -> Bool)? = nil,
        modifierKeyState: @escaping (CGKeyCode) -> Bool = {
            CGEventSource.keyState(.combinedSessionState, key: $0)
        }
    ) {
        self.mouseLocation = mouseLocation
        outerDisplayEdgePredicate = isAtOuterDisplayEdge ?? Self.isAtOuterDisplayEdge
        self.modifierKeyState = modifierKeyState
    }

    func install() -> Bool {
        if isInstalled { return true }
        let types: [CGEventType] = [
            .keyDown,
            .keyUp,
            .flagsChanged,
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func uninstall() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        runLoopSource = nil
        eventTap = nil
        resetActiveSwitcherSession(notifyHandler: true)
    }

    private static let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let controller = Unmanaged<GlobalInputController>.fromOpaque(userInfo).takeUnretainedValue()
        return controller.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
    }

    func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            resetActiveSwitcherSession(notifyHandler: true)
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return false
        }

        if type == .mouseMoved {
            let location = mouseLocation()
            pendingMousePoint = location
            if !mouseUpdateScheduled {
                mouseUpdateScheduled = true
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.mouseUpdateScheduled = false
                    guard let point = self.pendingMousePoint else { return }
                    self.pendingMousePoint = nil
                    self.handler?.pointerMoved(to: point)
                }
            }
            return false
        }

        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            let location = mouseLocation()
            enqueueHandlerWork { $0.pointerPressed(at: location) }
            return false
        }

        if type == .scrollWheel {
            let location = mouseLocation()
            let delta = event.scrollDelta
            guard abs(delta) >= 0.1 else { return false }

            let now = Date()
            if edgeGestureRecognized {
                guard now.timeIntervalSince(lastEdgeScrollAt) <= 0.45,
                      outerDisplayEdgePredicate(location) else {
                    resetEdgeGesture()
                    return false
                }
                lastEdgeScrollAt = now
                enqueueHandlerWork { $0.edgeScrolled(delta: delta) }
                return true
            }

            guard !isSwitcherVisible else {
                resetEdgeGesture()
                return false
            }
            guard outerDisplayEdgePredicate(location) else {
                resetEdgeGesture()
                return false
            }
            if now.timeIntervalSince(lastEdgeScrollAt) > 0.45 {
                edgeScrollAccumulator = 0
            }
            lastEdgeScrollAt = now
            edgeScrollAccumulator += delta
            guard abs(edgeScrollAccumulator) >= 7 else { return false }

            edgeGestureRecognized = true
            let accumulatedDelta = edgeScrollAccumulator
            enqueueHandlerWork { $0.edgeScrolled(delta: accumulatedDelta) }
            return true
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        if type == .flagsChanged {
            if configuration.enableFastSearch,
               keyCode == configuration.fastSearchModifier.keyCode {
                let nowHeld = modifierKeyState(CGKeyCode(configuration.fastSearchModifier.keyCode))
                if fastModifierHeld && !nowHeld && fastSearchActive {
                    cancelActiveSwitcherSession()
                    enqueueHandlerWork { $0.commitSwitcherSelection() }
                    return false
                }
                fastModifierHeld = nowHeld
            }

            if let cyclingModifier, !flags.contains(cyclingModifier) {
                cancelActiveSwitcherSession()
                enqueueHandlerWork { $0.commitSwitcherSelection() }
                return false
            }
            return false
        }

        if type == .keyUp {
            if keyCode == endingActionKeyCode {
                endingActionKeyCode = nil
                return true
            }
            return cyclingModifier != nil && (keyCode == KeyCode.tab || keyCode == KeyCode.grave)
        }

        guard type == .keyDown else { return false }

        if keyCode == endingActionKeyCode,
           event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return true
        }

        if configuration.enableFastSearch,
           fastModifierHeld,
           !flags.contains(.maskCommand),
           let text = event.text,
           text.rangeOfCharacter(from: .alphanumerics) != nil {
            if !fastSearchActive {
                fastSearchActive = true
                presentSwitcher(mode: .fastSearch, advanceImmediately: false)
            }
            enqueueHandlerWork { $0.appendSwitcherQuery(text) }
            return true
        }

        let normalizedFlags = flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])

        if keyCode == KeyCode.space, normalizedFlags == .maskControl {
            presentSwitcher(mode: .search, advanceImmediately: false)
            return true
        }

        if keyCode == KeyCode.tab,
           normalizedFlags == .maskCommand || normalizedFlags == [.maskCommand, .maskShift],
           configuration.replaceCommandTab {
            if !isSwitcherVisible {
                cyclingModifier = .maskCommand
                presentSwitcher(mode: .recent, advanceImmediately: true)
            } else {
                cyclingModifier = .maskCommand
                enqueueHandlerWork { $0.moveSwitcherSelection(by: flags.contains(.maskShift) ? -1 : 1) }
            }
            return true
        }

        if keyCode == KeyCode.tab,
           normalizedFlags == .maskAlternate || normalizedFlags == [.maskAlternate, .maskShift],
           configuration.enableOptionTab,
           (!configuration.enableFastSearch || !fastModifierHeld) {
            if !isSwitcherVisible {
                cyclingModifier = .maskAlternate
                presentSwitcher(mode: .recent, advanceImmediately: true)
            } else {
                cyclingModifier = .maskAlternate
                enqueueHandlerWork { $0.moveSwitcherSelection(by: flags.contains(.maskShift) ? -1 : 1) }
            }
            return true
        }

        if keyCode == KeyCode.grave,
           normalizedFlags == .maskCommand || normalizedFlags == [.maskCommand, .maskShift] {
            if !isSwitcherVisible {
                cyclingModifier = .maskCommand
                let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
                presentSwitcher(mode: .application(pid), advanceImmediately: true)
            } else {
                cyclingModifier = .maskCommand
                enqueueHandlerWork { $0.moveSwitcherSelection(by: flags.contains(.maskShift) ? -1 : 1) }
            }
            return true
        }

        guard isSwitcherVisible else { return false }

        if keyCode == KeyCode.s,
           cyclingModifier != nil,
           normalizedFlags == .maskCommand || normalizedFlags == .maskAlternate {
            enqueueHandlerWork { $0.beginSwitcherSearch() }
            return true
        }

        switch keyCode {
        case KeyCode.up, KeyCode.k:
            enqueueHandlerWork { $0.moveSwitcherSelection(by: -1) }
            return true
        case KeyCode.down, KeyCode.j:
            enqueueHandlerWork { $0.moveSwitcherSelection(by: 1) }
            return true
        case KeyCode.returnKey:
            cancelActiveSwitcherSession()
            enqueueHandlerWork { $0.commitSwitcherSelection() }
            return true
        case KeyCode.escape:
            cancelActiveSwitcherSession()
            enqueueHandlerWork { $0.dismissSwitcher() }
            return true
        case KeyCode.delete:
            enqueueHandlerWork { $0.deleteSwitcherQueryCharacter() }
            return true
        case KeyCode.w where normalizedFlags == .maskCommand:
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return true }
            enqueueHandlerWork { $0.performSwitcherAction(.close) }
            return true
        case KeyCode.m where normalizedFlags == .maskCommand:
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return true }
            cancelActiveSwitcherSession()
            endingActionKeyCode = keyCode
            enqueueHandlerWork { $0.performSwitcherAction(.minimize) }
            return true
        case KeyCode.h where normalizedFlags == .maskCommand:
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return true }
            cancelActiveSwitcherSession()
            endingActionKeyCode = keyCode
            enqueueHandlerWork { $0.performSwitcherAction(.hideApplication) }
            return true
        case KeyCode.q where normalizedFlags == .maskCommand:
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return true }
            enqueueHandlerWork { $0.performSwitcherAction(.quitApplication) }
            return true
        default:
            if configuration.directTyping,
               (!flags.contains(.maskCommand) && !flags.contains(.maskAlternate) || cyclingModifier != nil),
               let text = event.text,
               !text.isEmpty {
                enqueueHandlerWork { $0.appendSwitcherQuery(text) }
                return true
            }
            return false
        }
    }

    func cancelActiveSwitcherSession() {
        resetActiveSwitcherSession(notifyHandler: false, clearEndingActionKey: false)
    }

    private func resetActiveSwitcherSession(notifyHandler: Bool, clearEndingActionKey: Bool = true) {
        cyclingModifier = nil
        fastModifierHeld = false
        fastSearchActive = false
        presentationPending = false
        if clearEndingActionKey {
            endingActionKeyCode = nil
        }
        resetEdgeGesture()
        if notifyHandler {
            enqueueHandlerWork { $0.inputSessionDidReset() }
        }
    }

    private var isSwitcherVisible: Bool {
        if presentationPending { return true }
        if Thread.isMainThread { return MainActor.assumeIsolated { handler?.isSwitcherVisible ?? false } }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { handler?.isSwitcherVisible ?? false } }
    }

    private func presentSwitcher(mode: SwitcherMode, advanceImmediately: Bool) {
        presentationPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.handler?.presentSwitcher(mode: mode, advanceImmediately: advanceImmediately)
            self.presentationPending = false
        }
    }

    private func enqueueHandlerWork(_ operation: @escaping @MainActor (GlobalInputHandler) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let handler = self?.handler else { return }
            operation(handler)
        }
    }

    private func resetEdgeGesture() {
        edgeScrollAccumulator = 0
        edgeGestureRecognized = false
        lastEdgeScrollAt = .distantPast
    }

    private static func isAtOuterDisplayEdge(_ point: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return false }
        let atLeft = abs(point.x - screen.frame.minX) <= 6
        let atRight = abs(point.x - screen.frame.maxX) <= 6
        guard atLeft || atRight else { return false }

        let probeX = atLeft ? screen.frame.minX - 2 : screen.frame.maxX + 2
        let hasAdjacentScreen = NSScreen.screens.contains { other in
            other !== screen && other.frame.contains(CGPoint(x: probeX, y: point.y))
        }
        return !hasAdjacentScreen
    }
}

private enum KeyCode {
    static let returnKey: UInt16 = 36
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let grave: UInt16 = 50
    static let delete: UInt16 = 51
    static let escape: UInt16 = 53
    static let s: UInt16 = 1
    static let h: UInt16 = 4
    static let q: UInt16 = 12
    static let w: UInt16 = 13
    static let j: UInt16 = 38
    static let k: UInt16 = 40
    static let m: UInt16 = 46
    static let down: UInt16 = 125
    static let up: UInt16 = 126
}

private extension FastSearchModifier {
    var keyCode: UInt16 {
        switch self {
        case .rightOption: 61
        case .leftOption: 58
        case .function: 63
        }
    }

    var eventFlag: CGEventFlags {
        switch self {
        case .rightOption, .leftOption: .maskAlternate
        case .function: .maskSecondaryFn
        }
    }
}

private extension CGEvent {
    var scrollDelta: Double {
        let pointDelta = getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        if pointDelta != 0 { return Double(pointDelta) }
        return getDoubleValueField(.scrollWheelEventDeltaAxis1)
    }

    var text: String? {
        var length = 0
        keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        guard length > 0 else { return nil }
        var characters = [UniChar](repeating: 0, count: length)
        keyboardGetUnicodeString(maxStringLength: length, actualStringLength: &length, unicodeString: &characters)
        return String(utf16CodeUnits: characters, count: length)
    }
}
