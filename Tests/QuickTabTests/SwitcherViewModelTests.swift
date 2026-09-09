import AppKit
import Combine
import XCTest
@testable import QuickTab

@MainActor
final class SwitcherViewModelTests: XCTestCase {
    func testSelectionFollowsWindowIDWhenResultsReorder() {
        let first = window("first")
        let second = window("second")
        let third = window("third")
        let (viewModel, repository) = makeViewModel(windows: [first, second, third])

        viewModel.moveSelection(by: 1)
        repository.setWindows([third, first, second])

        XCTAssertEqual(viewModel.selectedWindowID, second.id)
        XCTAssertEqual(viewModel.selectedIndex, 2)
    }

    func testSelectionFallsBackToSameIndexWhenSelectedWindowDisappears() {
        let first = window("first")
        let second = window("second")
        let third = window("third")
        let (viewModel, repository) = makeViewModel(windows: [first, second, third])

        viewModel.moveSelection(by: 1)
        repository.setWindows([third, first])

        XCTAssertEqual(viewModel.selectedWindowID, first.id)
        XCTAssertEqual(viewModel.selectedIndex, 1)
    }

    func testSelectionClampsWhenLastSelectedWindowDisappears() {
        let first = window("first")
        let second = window("second")
        let third = window("third")
        let (viewModel, repository) = makeViewModel(windows: [first, second, third])

        viewModel.moveSelection(by: 2)
        repository.setWindows([first, second])

        XCTAssertEqual(viewModel.selectedWindowID, second.id)
        XCTAssertEqual(viewModel.selectedIndex, 1)
    }

    func testMoveSelectionWrapsInBothDirections() {
        let first = window("first")
        let second = window("second")
        let third = window("third")
        let (viewModel, _) = makeViewModel(windows: [first, second, third])

        viewModel.moveSelection(by: -1)
        XCTAssertEqual(viewModel.selectedWindowID, third.id)

        viewModel.moveSelection(by: 1)
        XCTAssertEqual(viewModel.selectedWindowID, first.id)
    }

    func testPresentDoesNotPublishUnchangedSelection() {
        let first = window("first")
        let (viewModel, _) = makeViewModel(windows: [first])
        var selections: [WindowID?] = []
        let cancellable = viewModel.$selectedWindowID
            .dropFirst()
            .sink { selections.append($0) }

        viewModel.present(.recent, pointerPosition: .zero)

        XCTAssertTrue(selections.isEmpty)
        withExtendedLifetime(cancellable) {}
    }

    func testSelectionClearsWhenResultsBecomeEmpty() {
        let first = window("first")
        let (viewModel, repository) = makeViewModel(windows: [first])

        repository.setWindows([])

        XCTAssertNil(viewModel.selectedWindowID)
        XCTAssertNil(viewModel.selectedResult)
    }

    func testPresentRequestsImmediateRevealForSelectedWindow() {
        let first = window("first")
        let second = window("second")
        let (viewModel, _) = makeViewModel(windows: [first, second], activeWindowID: first.id)

        viewModel.present(.recent, advanceImmediately: true, pointerPosition: .zero)

        XCTAssertEqual(
            viewModel.scrollRequest,
            SwitcherViewModel.ScrollRequest(windowID: second.id, animated: false)
        )
    }

    func testKeyboardMovementRequestsAnimatedScrollForSelectedWindow() {
        let first = window("first")
        let second = window("second")
        let (viewModel, _) = makeViewModel(windows: [first, second])

        viewModel.present(.recent, pointerPosition: .zero)
        viewModel.moveSelection(by: 1)

        XCTAssertEqual(
            viewModel.scrollRequest,
            SwitcherViewModel.ScrollRequest(windowID: second.id, animated: true)
        )
    }

    func testPointerSelectionDoesNotRequestProgrammaticScroll() {
        let first = window("first")
        let second = window("second")
        let (viewModel, _) = makeViewModel(windows: [first, second])
        var requests: [SwitcherViewModel.ScrollRequest] = []
        let cancellable = viewModel.$scrollRequest
            .compactMap { $0 }
            .sink { requests.append($0) }

        viewModel.present(.recent, pointerPosition: .zero)
        viewModel.handlePointerHover(over: second.id, at: CGPoint(x: 3, y: 0))

        XCTAssertEqual(viewModel.selectedWindowID, second.id)
        XCTAssertEqual(requests, [
            SwitcherViewModel.ScrollRequest(windowID: first.id, animated: false),
        ])
        withExtendedLifetime(cancellable) {}
    }

    func testStationaryPointerAndJitterDoNotChangeSelectionAfterPresenting() {
        let first = window("first")
        let second = window("second")
        let (viewModel, _) = makeViewModel(windows: [first, second])

        viewModel.present(.recent, pointerPosition: CGPoint(x: 100, y: 100))
        viewModel.handlePointerHover(over: second.id, at: CGPoint(x: 100, y: 100))
        viewModel.handlePointerHover(over: second.id, at: CGPoint(x: 101, y: 101))

        XCTAssertEqual(viewModel.selectedWindowID, first.id)
    }

    func testGapMovementUpdatesPointerAnchorWithoutOverridingKeyboardSelection() {
        let first = window("first")
        let second = window("second")
        let (viewModel, _) = makeViewModel(windows: [first, second])
        let gapLocation = CGPoint(x: 120, y: 100)

        viewModel.present(.recent, pointerPosition: CGPoint(x: 100, y: 100))
        viewModel.updatePointerAnchor(to: gapLocation)
        XCTAssertEqual(viewModel.selectedWindowID, first.id)

        viewModel.moveSelection(by: 1)
        viewModel.handlePointerHover(over: first.id, at: gapLocation)

        XCTAssertEqual(viewModel.selectedWindowID, second.id)
    }

    func testGenuinePointerMovementSelectsHoveredWindowAndUpdatesAnchor() {
        let first = window("first")
        let second = window("second")
        let third = window("third")
        let (viewModel, _) = makeViewModel(windows: [first, second, third])

        viewModel.present(.recent, pointerPosition: CGPoint(x: 100, y: 100))
        viewModel.handlePointerHover(over: second.id, at: CGPoint(x: 104, y: 100))

        XCTAssertEqual(viewModel.selectedWindowID, second.id)

        viewModel.handlePointerHover(over: third.id, at: CGPoint(x: 105, y: 100))
        XCTAssertEqual(viewModel.selectedWindowID, second.id)

        viewModel.handlePointerHover(over: third.id, at: CGPoint(x: 108, y: 100))
        XCTAssertEqual(viewModel.selectedWindowID, third.id)
    }

    func testKeyboardNavigationContinuesFromHoverAndStationaryHoverCannotSnapBack() {
        let first = window("first")
        let second = window("second")
        let third = window("third")
        let (viewModel, _) = makeViewModel(windows: [first, second, third])

        viewModel.present(.recent, pointerPosition: CGPoint(x: 100, y: 100))
        viewModel.handlePointerHover(over: second.id, at: CGPoint(x: 104, y: 100))
        viewModel.moveSelection(by: 1)

        XCTAssertEqual(viewModel.selectedWindowID, third.id)

        viewModel.handlePointerHover(over: second.id, at: CGPoint(x: 104, y: 100))
        XCTAssertEqual(viewModel.selectedWindowID, third.id)
    }

    func testCommitByIDActivatesExactWindow() async {
        let first = window("first")
        let second = window("second")
        let (viewModel, repository) = makeViewModel(windows: [first, second])
        let activated = expectation(description: "Exact window activated")
        repository.onActivate = { activated.fulfill() }
        var wasVisibleAtWillCommit: Bool?
        viewModel.onWillCommit = { wasVisibleAtWillCommit = viewModel.isVisible }

        viewModel.present(.recent, pointerPosition: .zero)
        viewModel.commit(second.id)

        XCTAssertEqual(wasVisibleAtWillCommit, true)
        XCTAssertFalse(viewModel.isVisible)
        await fulfillment(of: [activated], timeout: 1)
        XCTAssertEqual(repository.activatedWindowIDs, [second.id])
    }

    func testNewPresentationCancelsPendingActivationFromPreviousCommit() async throws {
        let first = window("first")
        let second = window("second")
        let (viewModel, repository) = makeViewModel(windows: [first, second])

        viewModel.present(.recent, pointerPosition: .zero)
        viewModel.commit(first.id)
        viewModel.present(.recent, pointerPosition: .zero)
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertTrue(repository.activatedWindowIDs.isEmpty)
        XCTAssertTrue(viewModel.isVisible)
    }

    func testDismissCancelsPendingActivationWhenAlreadyHidden() async throws {
        let first = window("first")
        let (viewModel, repository) = makeViewModel(windows: [first])

        viewModel.present(.recent, pointerPosition: .zero)
        viewModel.commit()
        XCTAssertFalse(viewModel.isVisible)

        viewModel.dismiss()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertTrue(repository.activatedWindowIDs.isEmpty)
    }

    func testInputSessionResetCancelsPendingActivationAfterCommit() async throws {
        let first = window("first")
        let (viewModel, repository) = makeViewModel(windows: [first])
        let controller = GlobalInputController()
        let handler = ViewModelInputHandler(viewModel: viewModel)
        controller.handler = handler

        viewModel.present(.recent, pointerPosition: .zero)
        viewModel.commit()
        controller.uninstall()
        await drainMainQueue()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertTrue(repository.activatedWindowIDs.isEmpty)
    }

    func testMinimizeDismissesBeforeSlowRepositoryActionReturns() {
        let first = window("first")
        let (viewModel, repository) = makeViewModel(windows: [first])
        repository.performDelay = 0.2
        viewModel.present(.recent, pointerPosition: .zero)

        let startedAt = Date()
        viewModel.perform(.minimize)

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.05)
        XCTAssertFalse(viewModel.isVisible)
    }

    func testFailedMinimizeDoesNotLeaveSwitcherVisible() async {
        let first = window("first")
        let (viewModel, repository) = makeViewModel(windows: [first])
        repository.performResult = false
        viewModel.present(.recent, pointerPosition: .zero)

        viewModel.perform(.minimize)

        XCTAssertFalse(viewModel.isVisible)
        await drainMainQueue()
        XCTAssertFalse(viewModel.isVisible)
    }

    func testMinimizeWithoutSelectionDismissesSwitcher() {
        let first = window("first")
        let (viewModel, repository) = makeViewModel(windows: [first])
        viewModel.present(.recent, pointerPosition: .zero)
        repository.setWindows([])

        viewModel.perform(.minimize)

        XCTAssertFalse(viewModel.isVisible)
    }

    func testNewPresentationIgnoresCompletionFromPreviousAction() async {
        let first = window("first")
        let second = window("second")
        let (viewModel, repository) = makeViewModel(windows: [first, second])
        repository.performDelay = 0.1
        let actionStarted = expectation(description: "Action started")
        repository.onPerform = { actionStarted.fulfill() }
        viewModel.present(.recent, pointerPosition: .zero)

        viewModel.perform(.close, keepVisible: true)
        await fulfillment(of: [actionStarted], timeout: 1)
        viewModel.present(.recent, pointerPosition: .zero)
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertTrue(viewModel.isVisible)
        XCTAssertEqual(viewModel.results.map(\.item.id), [first.id, second.id])
    }

    func testKeepVisibleActionRejectsRepeatedInputAndPreservesNewSelection() async {
        let first = window("first")
        let second = window("second")
        let (viewModel, repository) = makeViewModel(windows: [first, second])
        repository.performDelay = 0.1
        let actionStarted = expectation(description: "Action started")
        repository.onPerform = { actionStarted.fulfill() }
        viewModel.present(.recent, pointerPosition: .zero)

        viewModel.perform(.close, keepVisible: true)
        await fulfillment(of: [actionStarted], timeout: 1)
        viewModel.moveSelection(by: 1)
        viewModel.perform(.close, keepVisible: true)
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(repository.performedActions.count, 1)
        XCTAssertEqual(repository.performedActions.first?.1, first.id)
        XCTAssertEqual(viewModel.selectedWindowID, second.id)
    }

    func testCommandReleaseWaitsForCloseThenCommitsNextWindow() async throws {
        let first = window("first")
        let second = window("second")
        let (viewModel, repository) = makeViewModel(windows: [first, second], activeWindowID: first.id)
        let controller = GlobalInputController()
        let handler = ViewModelInputHandler(viewModel: viewModel)
        let actionStarted = expectation(description: "Close started")
        let activated = expectation(description: "Next window activated")
        repository.performDelay = 0.1
        repository.removePerformedWindowOnSuccess = true
        repository.onPerform = { actionStarted.fulfill() }
        repository.onActivate = { activated.fulfill() }
        controller.handler = handler
        viewModel.onWillCommit = { controller.cancelActiveSwitcherSession() }

        let tab = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: true))
        tab.flags = .maskCommand
        XCTAssertTrue(controller.handle(type: .keyDown, event: tab))
        await drainMainQueue()
        XCTAssertEqual(viewModel.selectedWindowID, second.id)

        let close = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 13, keyDown: true))
        close.flags = .maskCommand
        XCTAssertTrue(controller.handle(type: .keyDown, event: close))
        await fulfillment(of: [actionStarted], timeout: 1)

        let release = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: false))
        XCTAssertFalse(controller.handle(type: .flagsChanged, event: release))
        await fulfillment(of: [activated], timeout: 1)

        XCTAssertEqual(repository.performedActions.first?.1, second.id)
        XCTAssertEqual(repository.activatedWindowIDs, [first.id])
        XCTAssertFalse(viewModel.isVisible)
    }

    func testSlowActivationDoesNotBlockMainActor() async {
        let first = window("first")
        let (viewModel, repository) = makeViewModel(windows: [first])
        repository.activationDelay = 0.5
        viewModel.present(.recent, pointerPosition: .zero)

        let startedAt = Date()
        viewModel.commit()
        try? await Task.sleep(for: .milliseconds(60))

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.25)
        XCTAssertFalse(viewModel.isVisible)
        viewModel.dismiss()
    }

    func testCommitByIDAfterCommandCyclingPreventsReleaseRecommit() async throws {
        try await assertCommitByIDCancelsHeldCyclingSession(
            flags: .maskCommand,
            configuration: GlobalInputConfiguration()
        )
    }

    func testCommitByIDAfterOptionCyclingPreventsReleaseRecommit() async throws {
        try await assertCommitByIDCancelsHeldCyclingSession(
            flags: .maskAlternate,
            configuration: GlobalInputConfiguration(enableOptionTab: true)
        )
    }

    private func assertCommitByIDCancelsHeldCyclingSession(
        flags: CGEventFlags,
        configuration: GlobalInputConfiguration
    ) async throws {
        let first = window("first")
        let second = window("second")
        let (viewModel, repository) = makeViewModel(windows: [first, second])
        let controller = GlobalInputController()
        let handler = ViewModelInputHandler(viewModel: viewModel)
        let activated = expectation(description: "Exact pointer-selected window activated")
        repository.onActivate = { activated.fulfill() }
        controller.configuration = configuration
        controller.handler = handler
        viewModel.onWillCommit = { controller.cancelActiveSwitcherSession() }

        let tab = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: true))
        tab.flags = flags
        XCTAssertTrue(controller.handle(type: .keyDown, event: tab))
        await drainMainQueue()

        viewModel.commit(second.id)
        let releaseKey: CGKeyCode = flags == .maskAlternate ? 58 : 55
        let release = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: releaseKey, keyDown: false))
        XCTAssertFalse(controller.handle(type: .flagsChanged, event: release))

        await fulfillment(of: [activated], timeout: 1)
        XCTAssertEqual(repository.activatedWindowIDs, [second.id])
        XCTAssertEqual(handler.commitCount, 0)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func makeViewModel(
        windows: [WindowItem],
        activeWindowID: WindowID? = nil
    ) -> (SwitcherViewModel, TestWindowRepository) {
        let repository = TestWindowRepository(windows: windows, activeWindowID: activeWindowID)
        let viewModel = SwitcherViewModel(repository: repository)
        return (viewModel, repository)
    }

    private func window(_ fingerprint: String, processID: pid_t = 42) -> WindowItem {
        WindowItem(
            id: WindowID(processID: processID, fingerprint: fingerprint),
            processID: processID,
            appName: "Test App",
            bundleIdentifier: "com.example.test",
            title: fingerprint.capitalized,
            context: nil,
            icon: NSImage(),
            element: nil,
            frame: nil,
            screenID: nil,
            isMinimized: false,
            isHidden: false,
            lastActive: .distantPast
        )
    }
}

@MainActor
private final class TestWindowRepository: WindowRepositoryProtocol {
    private let windowsSubject: CurrentValueSubject<[WindowItem], Never>
    var activeWindowID: WindowID?
    private(set) var activatedWindowIDs: [WindowID] = []
    private(set) var performedActions: [(WindowAction, WindowID)] = []
    var onActivate: (() -> Void)?
    var onPerform: (() -> Void)?
    var activationDelay: TimeInterval = 0
    var performDelay: TimeInterval = 0
    var performResult = true
    var removePerformedWindowOnSuccess = false

    var windowsPublisher: AnyPublisher<[WindowItem], Never> {
        windowsSubject.eraseToAnyPublisher()
    }

    init(windows: [WindowItem], activeWindowID: WindowID?) {
        windowsSubject = CurrentValueSubject(windows)
        self.activeWindowID = activeWindowID
    }

    func setWindows(_ windows: [WindowItem]) {
        windowsSubject.send(windows)
    }

    func activate(_ item: WindowItem) async {
        if activationDelay > 0 {
            try? await Task.sleep(for: .milliseconds(Int64(activationDelay * 1_000)))
        }
        guard !Task.isCancelled else { return }
        activatedWindowIDs.append(item.id)
        onActivate?()
    }

    func perform(_ action: WindowAction, on item: WindowItem) async -> Bool {
        performedActions.append((action, item.id))
        onPerform?()
        if performDelay > 0 {
            try? await Task.sleep(for: .milliseconds(Int64(performDelay * 1_000)))
        }
        guard !Task.isCancelled, performResult else { return false }
        if removePerformedWindowOnSuccess {
            switch action {
            case .close:
                windowsSubject.send(windowsSubject.value.filter { $0.id != item.id })
            case .quitApplication:
                windowsSubject.send(windowsSubject.value.filter { $0.processID != item.processID })
            case .minimize, .hideApplication:
                break
            }
        }
        return true
    }
}

@MainActor
private final class ViewModelInputHandler: GlobalInputHandler {
    private let viewModel: SwitcherViewModel
    private(set) var commitCount = 0

    var isSwitcherVisible: Bool { viewModel.isVisible }

    init(viewModel: SwitcherViewModel) {
        self.viewModel = viewModel
    }

    func presentSwitcher(mode: SwitcherMode, advanceImmediately: Bool) {
        viewModel.present(mode, advanceImmediately: advanceImmediately, pointerPosition: .zero)
    }

    func moveSwitcherSelection(by offset: Int) { viewModel.moveSelection(by: offset) }
    func commitSwitcherSelection() {
        commitCount += 1
        viewModel.commit()
    }
    func dismissSwitcher() { viewModel.dismiss() }
    func performSwitcherAction(_ action: WindowAction) {
        viewModel.perform(action, keepVisible: action == .close || action == .quitApplication)
    }
    func pointerPressed(at point: CGPoint) {}
    func inputSessionDidReset() { viewModel.dismiss() }
    func inputTapDidDisable() {}
}
