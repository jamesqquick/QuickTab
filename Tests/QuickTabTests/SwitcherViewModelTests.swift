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
        XCTAssertEqual(viewModel.selectionOrigin, .programmatic)
    }

    func testGenuinePointerMovementSelectsHoveredWindowAndUpdatesAnchor() {
        let first = window("first")
        let second = window("second")
        let third = window("third")
        let (viewModel, _) = makeViewModel(windows: [first, second, third])

        viewModel.present(.recent, pointerPosition: CGPoint(x: 100, y: 100))
        viewModel.handlePointerHover(over: second.id, at: CGPoint(x: 104, y: 100))

        XCTAssertEqual(viewModel.selectedWindowID, second.id)
        XCTAssertEqual(viewModel.selectionOrigin, .pointer)

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
        XCTAssertEqual(viewModel.selectionOrigin, .keyboard)

        viewModel.handlePointerHover(over: second.id, at: CGPoint(x: 104, y: 100))
        XCTAssertEqual(viewModel.selectedWindowID, third.id)
        XCTAssertEqual(viewModel.selectionOrigin, .keyboard)
    }

    func testCommitByIDActivatesExactWindow() async {
        let first = window("first")
        let second = window("second")
        let (viewModel, repository) = makeViewModel(windows: [first, second])
        let activated = expectation(description: "Exact window activated")
        repository.onActivate = { activated.fulfill() }

        viewModel.present(.recent, pointerPosition: .zero)
        viewModel.commit(second.id)

        await fulfillment(of: [activated], timeout: 1)
        XCTAssertEqual(repository.activatedWindowIDs, [second.id])
    }

    private func makeViewModel(
        windows: [WindowItem],
        activeWindowID: WindowID? = nil
    ) -> (SwitcherViewModel, TestWindowRepository) {
        let repository = TestWindowRepository(windows: windows, activeWindowID: activeWindowID)
        let defaults = UserDefaults(suiteName: "SwitcherViewModelTests.\(UUID().uuidString)")!
        let viewModel = SwitcherViewModel(
            repository: repository,
            learnedSearch: LearnedSearchStore(defaults: defaults)
        )
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
    var onActivate: (() -> Void)?

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

    func activate(_ item: WindowItem) {
        activatedWindowIDs.append(item.id)
        onActivate?()
    }

    func perform(_ action: WindowAction, on item: WindowItem) -> Bool {
        true
    }
}
