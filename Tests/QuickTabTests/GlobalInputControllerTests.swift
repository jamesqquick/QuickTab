import CoreGraphics
import XCTest
@testable import QuickTab

@MainActor
final class GlobalInputControllerTests: XCTestCase {
    func testVisibleScrollWheelPassesThroughWithoutMovingSelection() throws {
        let controller = GlobalInputController()
        let handler = InputHandlerSpy()
        handler.isSwitcherVisible = true
        controller.handler = handler

        let scroll = try makeScrollEvent(delta: -4)

        XCTAssertFalse(controller.handle(type: .scrollWheel, event: scroll))
        XCTAssertTrue(handler.selectionOffsets.isEmpty)
    }

    func testVisibleSwitcherDoesNotStartEdgeScrollGesture() throws {
        let controller = GlobalInputController(
            mouseLocation: { .zero },
            isAtOuterDisplayEdge: { _ in true }
        )
        let handler = InputHandlerSpy()
        handler.isSwitcherVisible = true
        controller.handler = handler

        XCTAssertFalse(controller.handle(type: .scrollWheel, event: try makeScrollEvent(delta: 4)))
        XCTAssertFalse(controller.handle(type: .scrollWheel, event: try makeScrollEvent(delta: 4)))
        XCTAssertTrue(handler.edgeScrollDeltas.isEmpty)
    }

    func testControlSpacePresentationIsActiveForImmediatelyFollowingCharacter() throws {
        let controller = GlobalInputController()
        let handler = InputHandlerSpy()
        controller.handler = handler

        let controlSpace = try makeKeyEvent(keyCode: 49, flags: .maskControl)
        XCTAssertTrue(controller.handle(type: .keyDown, event: controlSpace))

        let character = try makeKeyEvent(keyCode: 0, text: "a")
        XCTAssertTrue(controller.handle(type: .keyDown, event: character))
        XCTAssertEqual(handler.queries, ["a"])
    }

    func testCycleChordOnVisibleSearchCommitsOnModifierRelease() throws {
        try assertVisibleCycleChordCommitsOnRelease(keyCode: 48, flags: .maskCommand)
    }

    func testOptionTabOnVisibleSearchCommitsOnModifierRelease() throws {
        try assertVisibleCycleChordCommitsOnRelease(
            keyCode: 48,
            flags: .maskAlternate,
            configuration: GlobalInputConfiguration(enableOptionTab: true)
        )
    }

    func testCommandBacktickOnVisibleSearchCommitsOnModifierRelease() throws {
        try assertVisibleCycleChordCommitsOnRelease(keyCode: 50, flags: .maskCommand)
    }

    func testExplicitSessionCancellationPreventsReleaseCommit() throws {
        let controller = GlobalInputController()
        let handler = InputHandlerSpy()
        controller.handler = handler

        let tab = try makeKeyEvent(keyCode: 48, flags: .maskCommand)
        XCTAssertTrue(controller.handle(type: .keyDown, event: tab))
        controller.cancelActiveSwitcherSession()
        handler.isSwitcherVisible = false

        let commandRelease = try makeKeyEvent(keyCode: 55)
        XCTAssertFalse(controller.handle(type: .flagsChanged, event: commandRelease))
        XCTAssertFalse(controller.handle(type: .keyDown, event: try makeKeyEvent(keyCode: 0, text: "a")))
        XCTAssertEqual(handler.commitCount, 0)
        XCTAssertTrue(handler.queries.isEmpty)
    }

    func testReturnCommitsOnceAndClearsCyclingSession() throws {
        let controller = GlobalInputController()
        let handler = InputHandlerSpy()
        controller.handler = handler

        XCTAssertTrue(controller.handle(
            type: .keyDown,
            event: try makeKeyEvent(keyCode: 48, flags: .maskCommand)
        ))
        XCTAssertTrue(controller.handle(type: .keyDown, event: try makeKeyEvent(keyCode: 36)))
        XCTAssertFalse(controller.handle(type: .flagsChanged, event: try makeKeyEvent(keyCode: 55)))

        XCTAssertEqual(handler.commitCount, 1)
    }

    func testEscapeDismissesAndClearsCyclingSession() throws {
        let controller = GlobalInputController()
        let handler = InputHandlerSpy()
        controller.handler = handler

        XCTAssertTrue(controller.handle(
            type: .keyDown,
            event: try makeKeyEvent(keyCode: 48, flags: .maskCommand)
        ))
        XCTAssertTrue(controller.handle(type: .keyDown, event: try makeKeyEvent(keyCode: 53)))
        XCTAssertFalse(controller.handle(type: .flagsChanged, event: try makeKeyEvent(keyCode: 55)))

        XCTAssertEqual(handler.dismissCount, 1)
        XCTAssertEqual(handler.commitCount, 0)
    }

    func testTapInterruptionClearsCyclingSession() throws {
        let controller = GlobalInputController()
        let handler = InputHandlerSpy()
        controller.handler = handler
        let event = try makeKeyEvent(keyCode: 48, flags: .maskCommand)

        XCTAssertTrue(controller.handle(type: .keyDown, event: event))
        XCTAssertFalse(controller.handle(type: .tapDisabledByTimeout, event: event))
        XCTAssertFalse(controller.handle(type: .flagsChanged, event: try makeKeyEvent(keyCode: 55)))
        XCTAssertEqual(handler.commitCount, 0)
    }

    func testReconfigurationClearsCyclingSession() throws {
        let controller = GlobalInputController()
        let handler = InputHandlerSpy()
        controller.handler = handler

        XCTAssertTrue(controller.handle(
            type: .keyDown,
            event: try makeKeyEvent(keyCode: 48, flags: .maskCommand)
        ))
        controller.configuration = GlobalInputConfiguration(directTyping: false)
        XCTAssertFalse(controller.handle(type: .flagsChanged, event: try makeKeyEvent(keyCode: 55)))
        XCTAssertEqual(handler.commitCount, 0)
    }

    func testPointerPressTypesRouteLocationToHandlerAndPassThrough() throws {
        let location = CGPoint(x: 120, y: 240)
        let controller = GlobalInputController(mouseLocation: { location })
        let handler = InputHandlerSpy()
        controller.handler = handler

        let presses: [(CGEventType, CGMouseButton)] = [
            (.leftMouseDown, .left),
            (.rightMouseDown, .right),
            (.otherMouseDown, .center),
        ]

        for (type, button) in presses {
            let click = try XCTUnwrap(CGEvent(
                mouseEventSource: nil,
                mouseType: type,
                mouseCursorPosition: .zero,
                mouseButton: button
            ))
            XCTAssertFalse(controller.handle(type: type, event: click))
        }

        XCTAssertEqual(handler.pointerPressPoints, [location, location, location])
    }

    func testRecognizedEdgeGestureContinuesRoutingAfterSwitcherBecomesVisible() throws {
        let controller = GlobalInputController(
            mouseLocation: { .zero },
            isAtOuterDisplayEdge: { _ in true }
        )
        let handler = InputHandlerSpy()
        handler.showSwitcherOnEdgeScroll = true
        controller.handler = handler

        XCTAssertFalse(controller.handle(type: .scrollWheel, event: try makeScrollEvent(delta: 4)))
        XCTAssertTrue(controller.handle(type: .scrollWheel, event: try makeScrollEvent(delta: 4)))
        XCTAssertTrue(controller.handle(type: .scrollWheel, event: try makeScrollEvent(delta: -1)))

        XCTAssertEqual(handler.edgeScrollDeltas, [8, -1])
        XCTAssertTrue(handler.selectionOffsets.isEmpty)
    }

    func testCommandQKeepsCyclingUntilCommandRelease() async throws {
        try await assertCyclingAction(keyCode: 12, expectedAction: .quitApplication)
    }

    func testCommandWKeepsCyclingUntilCommandRelease() async throws {
        try await assertCyclingAction(keyCode: 13, expectedAction: .close)
    }

    func testCommandMAutorepeatIsSuppressedAndEndsCycling() async throws {
        try await assertEndingAction(keyCode: 46, expectedAction: .minimize)
    }

    func testCommandHAutorepeatIsSuppressedAndEndsCycling() async throws {
        try await assertEndingAction(keyCode: 4, expectedAction: .hideApplication)
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

        await fulfillment(of: [actionReceived], timeout: 1)
        let commandRelease = try makeKeyEvent(keyCode: 55)
        XCTAssertFalse(controller.handle(type: .flagsChanged, event: commandRelease))
        await Task.yield()
        XCTAssertEqual(handler.actionCount, 1)
        XCTAssertEqual(handler.commitCount, 0)
    }

    private func assertVisibleCycleChordCommitsOnRelease(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        configuration: GlobalInputConfiguration = GlobalInputConfiguration()
    ) throws {
        let controller = GlobalInputController()
        let handler = InputHandlerSpy()
        handler.isSwitcherVisible = true
        controller.configuration = configuration
        controller.handler = handler

        let chord = try makeKeyEvent(keyCode: keyCode, flags: flags)
        XCTAssertTrue(controller.handle(type: .keyDown, event: chord))

        let modifierRelease = try makeKeyEvent(keyCode: flags == .maskAlternate ? 58 : 55)
        XCTAssertFalse(controller.handle(type: .flagsChanged, event: modifierRelease))
        XCTAssertEqual(handler.selectionOffsets, [1])
        XCTAssertEqual(handler.commitCount, 1)
    }

    private func makeKeyEvent(
        keyCode: CGKeyCode,
        flags: CGEventFlags = [],
        text: String? = nil
    ) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true))
        event.flags = flags
        if let text {
            var characters = Array(text.utf16)
            event.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: &characters)
        }
        return event
    }

    private func makeScrollEvent(delta: Int32) throws -> CGEvent {
        try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: delta,
            wheel2: 0,
            wheel3: 0
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
    var selectionOffsets: [Int] = []
    var queries: [String] = []
    var pointerPressPoints: [CGPoint] = []
    var edgeScrollDeltas: [Double] = []
    var showSwitcherOnEdgeScroll = false

    func presentSwitcher(mode: SwitcherMode, advanceImmediately: Bool) {
        isSwitcherVisible = true
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
    func appendSwitcherQuery(_ text: String) { queries.append(text) }
    func beginSwitcherSearch() {}
    func deleteSwitcherQueryCharacter() {}
    func dismissSwitcher() {
        dismissCount += 1
        isSwitcherVisible = false
    }
    func pointerMoved(to point: CGPoint) {}
    func pointerPressed(at point: CGPoint) { pointerPressPoints.append(point) }
    func edgeScrolled(delta: Double) {
        edgeScrollDeltas.append(delta)
        if showSwitcherOnEdgeScroll {
            isSwitcherVisible = true
        }
    }
}
