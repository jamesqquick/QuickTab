import AppKit
import Combine

@MainActor
final class SwitcherViewModel: ObservableObject {
    struct ScrollRequest: Equatable {
        let windowID: WindowID
        let animated: Bool
    }

    @Published private(set) var results: [WindowResult] = []
    @Published private(set) var selectedWindowID: WindowID?
    @Published private(set) var scrollRequest: ScrollRequest?
    @Published private(set) var mode: SwitcherMode = .recent
    @Published private(set) var isVisible = false

    var selectedResult: WindowResult? {
        guard let selectedWindowID else { return nil }
        return results.first { $0.item.id == selectedWindowID }
    }

    var selectedIndex: Int {
        guard let selectedWindowID else { return 0 }
        return results.firstIndex { $0.item.id == selectedWindowID } ?? 0
    }

    var modeLabel: String {
        switch mode {
        case .recent: "RECENT WINDOWS"
        case .application: "CURRENT APP"
        }
    }

    private let repository: any WindowRepositoryProtocol
    private var allWindows: [WindowItem] = []
    private var cancellables: Set<AnyCancellable> = []
    private var pointerAnchor: CGPoint?
    private var pendingActivation: Task<Void, Never>?
    private let pointerJitterThreshold: CGFloat = 2
    var onVisibilityChange: ((Bool) -> Void)?
    var onWillCommit: (() -> Void)?

    init(repository: any WindowRepositoryProtocol) {
        self.repository = repository
        repository.windowsPublisher
            .sink { [weak self] windows in
                guard let self else { return }
                self.allWindows = windows
                self.rebuildResults(preserveSelection: true)
            }
            .store(in: &cancellables)
    }

    func present(
        _ mode: SwitcherMode,
        advanceImmediately: Bool = false,
        pointerPosition: CGPoint = NSEvent.mouseLocation
    ) {
        pendingActivation?.cancel()
        pendingActivation = nil
        self.mode = mode
        rebuildResults(preserveSelection: false)
        if advanceImmediately, results.count > 1 {
            if let activeIndex = results.firstIndex(where: { $0.item.id == repository.activeWindowID }) {
                setSelection(results[(activeIndex + 1) % results.count].item.id)
            } else {
                setSelection(results.first?.item.id)
            }
        } else {
            setSelection(results.first?.item.id)
        }
        if let selectedWindowID {
            scrollRequest = ScrollRequest(windowID: selectedWindowID, animated: false)
        }
        pointerAnchor = pointerPosition
        isVisible = true
        onVisibilityChange?(true)
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let index = ((selectedIndex + offset) % results.count + results.count) % results.count
        setSelection(results[index].item.id)
        scrollRequest = ScrollRequest(windowID: results[index].item.id, animated: true)
    }

    func handlePointerHover(over id: WindowID, at point: CGPoint) {
        guard isVisible, results.contains(where: { $0.id == id }) else { return }
        guard let pointerAnchor else {
            self.pointerAnchor = point
            return
        }
        let deltaX = point.x - pointerAnchor.x
        let deltaY = point.y - pointerAnchor.y
        guard deltaX * deltaX + deltaY * deltaY > pointerJitterThreshold * pointerJitterThreshold else { return }
        self.pointerAnchor = point
        setSelection(id)
    }

    func updatePointerAnchor(to point: CGPoint) {
        pointerAnchor = point
    }

    func commit() {
        commit(selectedResult)
    }

    func commit(_ id: WindowID) {
        commit(results.first { $0.item.id == id })
    }

    private func commit(_ result: WindowResult?) {
        guard isVisible else { return }
        onWillCommit?()
        guard let result else {
            dismiss()
            return
        }
        dismiss()
        pendingActivation?.cancel()
        pendingActivation = Task { [repository] in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            repository.activate(result.item)
        }
    }

    func dismiss() {
        pendingActivation?.cancel()
        pendingActivation = nil
        guard isVisible else { return }
        isVisible = false
        onVisibilityChange?(false)
    }

    func perform(_ action: WindowAction, keepVisible: Bool = false) {
        guard let result = selectedResult else { return }
        let adjacentIndex = selectedIndex
        guard repository.perform(action, on: result.item) else { return }
        if keepVisible {
            switch action {
            case .close:
                allWindows.removeAll { $0.id == result.item.id }
            case .quitApplication:
                allWindows.removeAll { $0.processID == result.item.processID }
            case .minimize, .hideApplication:
                break
            }
            rebuildResults(preserveSelection: false, preferredIndex: adjacentIndex)
        } else {
            dismiss()
        }
    }

    private func rebuildResults(preserveSelection: Bool, preferredIndex: Int? = nil) {
        let previousSelectedID = selectedWindowID
        let previousIndex = selectedIndex
        let source: [WindowItem]
        if case let .application(processID) = mode {
            source = allWindows.filter { $0.processID == processID }
        } else {
            source = allWindows
        }

        results = source.map { WindowResult(item: $0) }

        if preserveSelection,
           let previousSelectedID,
           results.contains(where: { $0.item.id == previousSelectedID }) {
            return
        } else if results.isEmpty {
            setSelection(nil)
        } else if let preferredIndex {
            setSelection(results[min(preferredIndex, results.count - 1)].item.id)
        } else if !preserveSelection {
            setSelection(results.first?.item.id)
        } else {
            setSelection(results[min(previousIndex, results.count - 1)].item.id)
        }

        if isVisible, selectedWindowID != previousSelectedID, let selectedWindowID {
            scrollRequest = ScrollRequest(windowID: selectedWindowID, animated: false)
        }
    }

    private func setSelection(_ id: WindowID?) {
        guard selectedWindowID != id else { return }
        selectedWindowID = id
    }
}
