import CoreGraphics
import XCTest
@testable import QuickTab

@MainActor
final class GlobalInputControllerTests: XCTestCase {
    func testCommandQKeepsCyclingUntilCommandRelease() async throws {
        try await assertCyclingAction(keyCode: 12, expectedAction: .quitApplication)
    }

    func testCommandWKeepsCyclingUntilCommandRelease() async throws {
        try await assertCyclingAction(keyCode: 13, expectedAction: .close)
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
}

@MainActor
private final class InputHandlerSpy: GlobalInputHandler {
    var isSwitcherVisible = false
    var onPresent: (() -> Void)?
    var onAction: ((WindowAction) -> Void)?
    var onCommit: (() -> Void)?
    var lastAction: WindowAction?
    var actionCount = 0

    func presentSwitcher(mode: SwitcherMode, advanceImmediately: Bool) {
        isSwitcherVisible = true
        onPresent?()
    }

    func commitSwitcherSelection() { onCommit?() }
    func performSwitcherAction(_ action: WindowAction) {
        lastAction = action
        actionCount += 1
        onAction?(action)
    }
    func moveSwitcherSelection(by offset: Int) {}
    func appendSwitcherQuery(_ text: String) {}
    func beginSwitcherSearch() {}
    func deleteSwitcherQueryCharacter() {}
    func dismissSwitcher() {}
    func pointerMoved(to point: CGPoint) {}
    func edgeScrolled(delta: Double) {}
}
