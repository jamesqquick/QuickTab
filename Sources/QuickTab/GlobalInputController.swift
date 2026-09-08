import AppKit
@preconcurrency import CoreGraphics

struct GlobalInputConfiguration {
    var replaceCommandTab = true
    var enableOptionTab = false
}

@MainActor
protocol GlobalInputHandler: AnyObject {
    var isSwitcherVisible: Bool { get }
    func presentSwitcher(mode: SwitcherMode, advanceImmediately: Bool)
    func moveSwitcherSelection(by offset: Int)
    func commitSwitcherSelection()
    func dismissSwitcher()
    func performSwitcherAction(_ action: WindowAction)
    func pointerPressed(at point: CGPoint)
    func inputSessionDidReset()
}

@MainActor
final class GlobalInputController {
    weak var handler: GlobalInputHandler?
    var configuration = GlobalInputConfiguration() {
        didSet { resetActiveSwitcherSession(notifyHandler: true) }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var cyclingModifier: CGEventFlags?
    private var presentationPending = false
    private var presentationGeneration: UInt = 0
    private var endingActionKeyCode: UInt16?
    private let mouseLocation: () -> CGPoint

    var isInstalled: Bool { eventTap != nil }

    init(
        mouseLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation }
    ) {
        self.mouseLocation = mouseLocation
    }

    func install() -> Bool {
        if isInstalled { return true }
        let types: [CGEventType] = [
            .keyDown,
            .keyUp,
            .flagsChanged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<GlobalInputController>.fromOpaque(userInfo).takeUnretainedValue()
                return MainActor.assumeIsolated {
                    controller.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
                }
            },
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

    func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            resetActiveSwitcherSession(notifyHandler: true)
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return false
        }

        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            guard isSwitcherVisible else { return false }
            let location = mouseLocation()
            let generation = presentationGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.presentationGeneration == generation,
                      let handler = self.handler else { return }
                handler.pointerPressed(at: location)
            }
            return false
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        if type == .flagsChanged {
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

        let normalizedFlags = flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])

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
           configuration.enableOptionTab {
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

        switch keyCode {
        case KeyCode.up:
            enqueueHandlerWork { $0.moveSwitcherSelection(by: -1) }
            return true
        case KeyCode.down:
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
            return false
        }
    }

    func cancelActiveSwitcherSession() {
        resetActiveSwitcherSession(notifyHandler: false, clearEndingActionKey: false)
    }

    func registerSwitcherPresentation() {
        guard !presentationPending else { return }
        presentationGeneration &+= 1
    }

    private func resetActiveSwitcherSession(notifyHandler: Bool, clearEndingActionKey: Bool = true) {
        presentationGeneration &+= 1
        cyclingModifier = nil
        presentationPending = false
        if clearEndingActionKey {
            endingActionKeyCode = nil
        }
        if notifyHandler {
            enqueueHandlerWork { $0.inputSessionDidReset() }
        }
    }

    private var isSwitcherVisible: Bool {
        presentationPending || handler?.isSwitcherVisible == true
    }

    private func presentSwitcher(mode: SwitcherMode, advanceImmediately: Bool) {
        presentationGeneration &+= 1
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

}

private enum KeyCode {
    static let returnKey: UInt16 = 36
    static let tab: UInt16 = 48
    static let grave: UInt16 = 50
    static let escape: UInt16 = 53
    static let h: UInt16 = 4
    static let q: UInt16 = 12
    static let w: UInt16 = 13
    static let m: UInt16 = 46
    static let down: UInt16 = 125
    static let up: UInt16 = 126
}
