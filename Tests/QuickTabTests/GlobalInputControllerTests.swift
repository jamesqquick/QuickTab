import CoreGraphics
import XCTest
@testable import QuickTab

@MainActor
final class GlobalInputControllerTests: XCTestCase {
    func testControlSpacePresentationIsActiveForImmediatelyFollowingCharacter() async throws {
        let controller = GlobalInputController()
        let handler = InputHandlerSpy()
        controller.handler = handler

        let controlSpace = try makeKeyEvent(keyCode: 49, flags: .maskControl)
        XCTAssertTrue(controller.handle(type: .keyDown, event: controlSpace))

        let character = try makeKeyEvent(keyCode: 0, text: "a")
        XCTAssertTrue(controller.handle(type: .keyDown, event: character))
        XCTAssertTrue(handler.queries.isEmpty)

        await drainMainQueue()
        XCTAssertEqual(handler.queries, ["a"])
        XCTAssertEqual(handler.events, ["present", "query:a"])
    }

    func testCycleChordOnVisibleSearchCommitsOnModifierRelease() async throws {
        try await assertVisibleCycleChordCommitsOnRelease(keyCode: 48, flags: .maskCommand)
    }

    func testOptionTabOnVisibleSearchCommitsOnModifierRelease() async throws {
        try await assertVisibleCycleChordCommitsOnRelease(
            keyCode: 48,
            flags: .maskAlternate,
            configuration: GlobalInputConfiguration(enableOptionTab: true)
        )
    }

    func testCommandBacktickOnVisibleSearchCommitsOnModifierRelease() async throws {
        try await assertVisibleCycleChordCommitsOnRelease(keyCode: 50, flags: .maskCommand)
    }

    func testExplicitSessionCancellationPreventsReleaseCommit() async throws {
        let controller = GlobalInputController()
        let handler = InputHandlerSpy()
        controller.handler = handler

        let tab = try makeKeyEvent(keyCode: 48, flags: .maskCommand)
        XCTAssertTrue(controller.handle(type: .keyDown, event: tab))
        await drainMainQueue()
        controller.cancelActiveSwitcherSession()
        controller.cancelActiveSwitcherSession()
        handler.isSwitcherVisible = false

        let commandRelease = try makeKeyEvent(keyCode: 55)
        XCTAssertFalse(controller.handle(type: .flagsChanged, event: commandRelease))
        XCTAssertFalse(controller.handle(type: .keyDown, event: try makeKeyEvent(keyCode: 0, text: "a")))
        XCTAssertEqual(handler.commitCount, 0)
        XCTAssertEqual(handler.inputSessionResetCount, 0)
        XCTAssertTrue(handler.queries.isEmpty)
    }

    func testReturnCommitsOnceAndClearsCyclingSession() async throws {
        let controller = GlobalInputController()
        let handler = InputHandlerSpy()
        controller.handler = handler

        XCTAssertTrue(controller.handle(
            type: .keyDown,
            event: try makeKeyEvent(keyCode: 48, flags: .maskCommand)
        ))
        XCTAssertTrue(controller.handle(type: .keyDown, event: try makeKeyEvent(keyCode: 36)))
        XCTAssertFalse(controller.handle(type: .flagsChanged, event: try makeKeyEvent(keyCode: 55)))

        await drainMainQueue()
        XCTAssertEqual(handler.commitCount, 1)
    }

    func testEscapeDismissesAndClearsCyclingSession() async throws {
        let controller = GlobalInputController()
        let handler = InputHandlerSpy()
        controller.handler = handler

        XCTAssertTrue(controller.handle(
            type: .keyDown,
            event: try makeKeyEvent(keyCode: 48, flags: .maskCommand)
        ))
        XCTAssertTrue(controller.handle(type: .keyDown, event: try makeKeyEvent(keyCode: 53)))
        XCTAssertFalse(controller.handle(type: .flagsChanged, event: try makeKeyEvent(keyCode: 55)))

        await drainMainQueue()
        XCTAssertEqual(handler.dismissCount, 1)
        XCTAssertEqual(handler.commitCount, 0)
    }

    func testTapInterruptionClearsCyclingSessionAndDismissesSwitcher() async throws {
        let controller = GlobalInputController()
        let handler = InputHandlerSpy()
        controller.handler = handler
        let event = try makeKeyEvent(keyCode: 48, flags: .maskCommand)

        XCTAssertTrue(controller.handle(type: .keyDown, event: event))
        await drainMainQueue()
        XCTAssertTrue(handler.isSwitcherVisible)

        XCTAssertFalse(controller.handle(type: .tapDisabledByTimeout, event: event))
        XCTAssertFalse(controller.handle(type: .flagsChanged, event: try makeKeyEvent(keyCode: 55)))
        XCTAssertEqual(handler.inputSessionResetCount, 0)
        XCTAssertTrue(handler.isSwitcherVisible)

        await drainMainQueue()
        XCTAssertEqual(handler.commitCount, 0)
        XCTAssertEqual(handler.inputSessionResetCount, 1)
        XCTAssertEqual(handler.dismissCount, 1)
        XCTAssertFalse(handler.isSwitcherVisible)
    }

    func testReconfigurationClearsCyclingSessionAndDismissesSwitcher() async throws {
        let controller = GlobalInputController()
        let handler = InputHandlerSpy()
        controller.handler = handler

        XCTAssertTrue(controller.handle(
            type: .keyDown,
            event: try makeKeyEvent(keyCode: 48, flags: .maskCommand)
        ))
        await drainMainQueue()
        XCTAssertTrue(handler.isSwitcherVisible)

        controller.configuration = GlobalInputConfiguration(directTyping: false)
        XCTAssertFalse(controller.handle(type: .flagsChanged, event: try makeKeyEvent(keyCode: 55)))
        XCTAssertEqual(handler.inputSessionResetCount, 0)
        XCTAssertTrue(handler.isSwitcherVisible)

        await drainMainQueue()
        XCTAssertEqual(handler.commitCount, 0)
        XCTAssertEqual(handler.inputSessionResetCount, 1)
        XCTAssertEqual(handler.dismissCount, 1)
        XCTAssertFalse(handler.isSwitcherVisible)
    }

    func testUninstallResetsInputSessionAndDismissesSwitcher() async throws {
        let controller = GlobalInputController()
        let handler = InputHandlerSpy()
        controller.handler = handler

        XCTAssertTrue(controller.handle(
            type: .keyDown,
            event: try makeKeyEvent(keyCode: 48, flags: .maskCommand)
        ))
        await drainMainQueue()
        XCTAssertTrue(handler.isSwitcherVisible)

        controller.uninstall()

        XCTAssertEqual(handler.inputSessionResetCount, 0)
        XCTAssertTrue(handler.isSwitcherVisible)
        await drainMainQueue()
        XCTAssertEqual(handler.inputSessionResetCount, 1)
        XCTAssertEqual(handler.dismissCount, 1)
        XCTAssertFalse(handler.isSwitcherVisible)
        XCTAssertFalse(controller.handle(type: .flagsChanged, event: try makeKeyEvent(keyCode: 55)))
        XCTAssertEqual(handler.commitCount, 0)
    }

    func testPointerPressTypesRouteLocationToHandlerAndPassThrough() async throws {
        var location = CGPoint.zero
        let controller = GlobalInputController(mouseLocation: { location })
        let handler = InputHandlerSpy()
        handler.isSwitcherVisible = true
        controller.handler = handler

        let presses: [(CGEventType, CGMouseButton, CGPoint)] = [
            (.leftMouseDown, .left, CGPoint(x: 120, y: 240)),
            (.rightMouseDown, .right, CGPoint(x: 220, y: 340)),
            (.otherMouseDown, .center, CGPoint(x: 320, y: 440)),
        ]

        for (type, button, eventLocation) in presses {
            location = eventLocation
            let click = try XCTUnwrap(CGEvent(
                mouseEventSource: nil,
                mouseType: type,
                mouseCursorPosition: .zero,
                mouseButton: button
            ))
            XCTAssertFalse(controller.handle(type: type, event: click))
        }
        location = CGPoint(x: 999, y: 999)

        await drainMainQueue()
        XCTAssertEqual(handler.pointerPressPoints, presses.map { $0.2 })
    }

    func testHiddenPointerPressIsNotDeliveredAfterPresentation() async throws {
        let location = CGPoint(x: 120, y: 240)
        let controller = GlobalInputController(mouseLocation: { location })
        let handler = InputHandlerSpy()
        controller.handler = handler

        XCTAssertFalse(controller.handle(type: .leftMouseDown, event: try makeMouseDownEvent()))
        XCTAssertTrue(controller.handle(type: .keyDown, event: try makeKeyEvent(keyCode: 49, flags: .maskControl)))

        await drainMainQueue()
        XCTAssertTrue(handler.pointerPressPoints.isEmpty)
        XCTAssertTrue(handler.isSwitcherVisible)
    }

    func testOldSessionPointerPressIsNotDeliveredToNewPresentation() async throws {
        let location = CGPoint(x: 120, y: 240)
        let controller = GlobalInputController(mouseLocation: { location })
        let handler = InputHandlerSpy()
        handler.isSwitcherVisible = true
        controller.handler = handler

        XCTAssertFalse(controller.handle(type: .leftMouseDown, event: try makeMouseDownEvent()))
        controller.uninstall()
        XCTAssertTrue(controller.handle(type: .keyDown, event: try makeKeyEvent(keyCode: 49, flags: .maskControl)))

        await drainMainQueue()
        XCTAssertTrue(handler.pointerPressPoints.isEmpty)
        XCTAssertTrue(handler.isSwitcherVisible)
    }

    func testExternalPresentationInvalidatesQueuedPointerPress() async throws {
        let location = CGPoint(x: 120, y: 240)
        let controller = GlobalInputController(mouseLocation: { location })
        let handler = InputHandlerSpy()
        handler.isSwitcherVisible = true
        controller.handler = handler

        XCTAssertFalse(controller.handle(type: .leftMouseDown, event: try makeMouseDownEvent()))
        controller.registerSwitcherPresentation()
        handler.presentSwitcher(mode: .search, advanceImmediately: false)

        await drainMainQueue()
        XCTAssertTrue(handler.pointerPressPoints.isEmpty)
    }

    func testInputPresentationRegistrationPreservesSameSessionPointerPress() async throws {
        let location = CGPoint(x: 120, y: 240)
        let controller = GlobalInputController(mouseLocation: { location })
        let handler = InputHandlerSpy()
        handler.onPresent = { controller.registerSwitcherPresentation() }
        controller.handler = handler

        XCTAssertTrue(controller.handle(type: .keyDown, event: try makeKeyEvent(keyCode: 49, flags: .maskControl)))
        XCTAssertFalse(controller.handle(type: .leftMouseDown, event: try makeMouseDownEvent()))

        await drainMainQueue()
        XCTAssertEqual(handler.pointerPressPoints, [location])
    }

    func testSameSessionPointerPressIsDelivered() async throws {
        let location = CGPoint(x: 120, y: 240)
        let controller = GlobalInputController(mouseLocation: { location })
        let handler = InputHandlerSpy()
        handler.isSwitcherVisible = true
        controller.handler = handler

        XCTAssertFalse(controller.handle(type: .leftMouseDown, event: try makeMouseDownEvent()))
        XCTAssertTrue(handler.pointerPressPoints.isEmpty)

        await drainMainQueue()
        XCTAssertEqual(handler.pointerPressPoints, [location])
    }

    func testPanelPolicyHitTestsVisibleRoundedContent() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 300)

        XCTAssertTrue(SwitcherPanelController.containsVisibleContent(CGPoint(x: 300, y: 250), panelFrame: frame))
        XCTAssertTrue(SwitcherPanelController.containsVisibleContent(CGPoint(x: 118, y: 250), panelFrame: frame))
        XCTAssertFalse(SwitcherPanelController.containsVisibleContent(CGPoint(x: 110, y: 250), panelFrame: frame))
        XCTAssertFalse(SwitcherPanelController.containsVisibleContent(CGPoint(x: 50, y: 50), panelFrame: frame))
        XCTAssertFalse(SwitcherPanelController.containsVisibleContent(CGPoint(x: 120, y: 120), panelFrame: frame))
        XCTAssertTrue(SwitcherPanelController.containsVisibleContent(CGPoint(x: 130, y: 130), panelFrame: frame))
        XCTAssertFalse(SwitcherPanelController.shouldDismissPointerPress(at: CGPoint(x: 300, y: 250), panelFrames: [frame]))
        XCTAssertTrue(SwitcherPanelController.shouldDismissPointerPress(at: CGPoint(x: 110, y: 250), panelFrames: [frame]))
    }

    func testCommandQKeepsCyclingUntilCommandRelease() async throws {
        try await assertCyclingAction(keyCode: 12, expectedAction: .quitApplication)
    }

    func testCommandWKeepsCyclingUntilCommandRelease() async throws {
        try await assertCyclingAction(keyCode: 13, expectedAction: .close)
    }

    func testActionHandlerIsNotInvokedBeforeHandleReturns() async throws {
        let controller = GlobalInputController()
        let handler = InputHandlerSpy()
        handler.isSwitcherVisible = true
        controller.handler = handler
        let actionReceived = expectation(description: "Action received asynchronously")
        handler.onAction = { _ in actionReceived.fulfill() }

        XCTAssertTrue(controller.handle(
            type: .keyDown,
            event: try makeKeyEvent(keyCode: 13, flags: .maskCommand)
        ))
        XCTAssertEqual(handler.actionCount, 0)

        await fulfillment(of: [actionReceived], timeout: 1)
        XCTAssertEqual(handler.actionCount, 1)
    }

    func testCommandMAutorepeatIsSuppressedAndEndsCycling() async throws {
        try await assertEndingAction(keyCode: 46, expectedAction: .minimize)
    }

    func testCommandHAutorepeatIsSuppressedAndEndsCycling() async throws {
        try await assertEndingAction(keyCode: 4, expectedAction: .hideApplication)
    }

    func testEndingActionsPassThroughWithoutSwitcherSession() async throws {
        let controller = GlobalInputController()
        let handler = InputHandlerSpy()
        controller.handler = handler

        XCTAssertFalse(controller.handle(
            type: .keyDown,
            event: try makeKeyEvent(keyCode: 46, flags: .maskCommand)
        ))
        XCTAssertFalse(controller.handle(
            type: .keyDown,
            event: try makeKeyEvent(keyCode: 4, flags: .maskCommand)
        ))

        await drainMainQueue()
        XCTAssertEqual(handler.actionCount, 0)
    }

    private func assertCyclingAction(keyCode: CGKeyCode, expectedAction: WindowAction) async throws {
        let controller = GlobalInputController()
        let handler = InputHandlerSpy()
        controller.handler = handler

        let presented = expectation(description: "Switcher presented")
        handler.onPresent = { presented.fulfill() }
        let tab = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: true))
        tab.flags = .maskCommand
        XCTAssertTrue(controller.handle(type: .keyDown, event: tab))

        let actionReceived = expectation(description: "Action received")
        handler.onAction = { action in
            XCTAssertEqual(action, expectedAction)
            actionReceived.fulfill()
        }
        let action = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true))
        action.flags = .maskCommand
        XCTAssertTrue(controller.handle(type: .keyDown, event: action))

        let repeatedAction = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true))
        repeatedAction.flags = .maskCommand
        repeatedAction.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        XCTAssertTrue(controller.handle(type: .keyDown, event: repeatedAction))

        let committed = expectation(description: "Selection committed on Command release")
        handler.onCommit = { committed.fulfill() }
        let commandRelease = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: false))
        commandRelease.flags = []
        XCTAssertFalse(controller.handle(type: .flagsChanged, event: commandRelease))
        await fulfillment(of: [presented, actionReceived, committed], timeout: 1)
        XCTAssertEqual(handler.lastAction, expectedAction)
        XCTAssertEqual(handler.actionCount, 1)
    }

    private func assertEndingAction(keyCode: CGKeyCode, expectedAction: WindowAction) async throws {
        let controller = GlobalInputController()
        let handler = InputHandlerSpy()
        controller.handler = handler

        let tab = try makeKeyEvent(keyCode: 48, flags: .maskCommand)
        XCTAssertTrue(controller.handle(type: .keyDown, event: tab))

        let actionReceived = expectation(description: "Action received once")
        handler.onAction = { action in
            XCTAssertEqual(action, expectedAction)
            actionReceived.fulfill()
        }
        let action = try makeKeyEvent(keyCode: keyCode, flags: .maskCommand)
        XCTAssertTrue(controller.handle(type: .keyDown, event: action))

        let repeatedAction = try makeKeyEvent(keyCode: keyCode, flags: .maskCommand)
        repeatedAction.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        XCTAssertTrue(controller.handle(type: .keyDown, event: repeatedAction))

        let actionRelease = try makeKeyEvent(keyCode: keyCode, keyDown: false)
        XCTAssertTrue(controller.handle(type: .keyUp, event: actionRelease))

        let repeatedActionAfterRelease = try makeKeyEvent(keyCode: keyCode, flags: .maskCommand)
        repeatedActionAfterRelease.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        XCTAssertFalse(controller.handle(type: .keyDown, event: repeatedActionAfterRelease))

        let commandRelease = try makeKeyEvent(keyCode: 55)
        XCTAssertFalse(controller.handle(type: .flagsChanged, event: commandRelease))
        await fulfillment(of: [actionReceived], timeout: 1)
        await drainMainQueue()
        XCTAssertEqual(handler.actionCount, 1)
        XCTAssertEqual(handler.commitCount, 0)
        XCTAssertTrue(handler.queries.isEmpty)
    }

    private func assertVisibleCycleChordCommitsOnRelease(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        configuration: GlobalInputConfiguration = GlobalInputConfiguration()
    ) async throws {
        let controller = GlobalInputController()
        let handler = InputHandlerSpy()
        handler.isSwitcherVisible = true
        controller.configuration = configuration
        controller.handler = handler

        let chord = try makeKeyEvent(keyCode: keyCode, flags: flags)
        XCTAssertTrue(controller.handle(type: .keyDown, event: chord))

        let modifierRelease = try makeKeyEvent(keyCode: flags == .maskAlternate ? 58 : 55)
        XCTAssertFalse(controller.handle(type: .flagsChanged, event: modifierRelease))
        await drainMainQueue()
        XCTAssertEqual(handler.selectionOffsets, [1])
        XCTAssertEqual(handler.commitCount, 1)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func makeKeyEvent(
        keyCode: CGKeyCode,
        flags: CGEventFlags = [],
        keyDown: Bool = true,
        text: String? = nil
    ) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown))
        event.flags = flags
        if let text {
            var characters = Array(text.utf16)
            event.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: &characters)
        }
        return event
    }

    private func makeMouseDownEvent() throws -> CGEvent {
        try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: .zero,
            mouseButton: .left
        ))
    }
}

@MainActor
private final class InputHandlerSpy: GlobalInputHandler {
    var isSwitcherVisible = false
    var onPresent: (() -> Void)?
    var onAction: ((WindowAction) -> Void)?
    var onCommit: (() -> Void)?
    var lastAction: WindowAction?
    var actionCount = 0
    var commitCount = 0
    var dismissCount = 0
    var inputSessionResetCount = 0
    var selectionOffsets: [Int] = []
    var queries: [String] = []
    var pointerPressPoints: [CGPoint] = []
    var events: [String] = []

    func presentSwitcher(mode: SwitcherMode, advanceImmediately: Bool) {
        isSwitcherVisible = true
        events.append("present")
        onPresent?()
    }

    func commitSwitcherSelection() {
        commitCount += 1
        onCommit?()
    }
    func performSwitcherAction(_ action: WindowAction) {
        lastAction = action
        actionCount += 1
        onAction?(action)
    }
    func moveSwitcherSelection(by offset: Int) { selectionOffsets.append(offset) }
    func appendSwitcherQuery(_ text: String) {
        queries.append(text)
        events.append("query:\(text)")
    }
    func beginSwitcherSearch() {}
    func deleteSwitcherQueryCharacter() {}
    func dismissSwitcher() {
        dismissCount += 1
        isSwitcherVisible = false
    }
    func pointerMoved(to point: CGPoint) {}
    func pointerPressed(at point: CGPoint) { pointerPressPoints.append(point) }
    func inputSessionDidReset() {
        inputSessionResetCount += 1
        dismissSwitcher()
    }
}
