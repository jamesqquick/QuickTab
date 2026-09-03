import AppKit
import Combine

@MainActor
final class SwitcherViewModel: ObservableObject {
    struct ScrollRequest: Equatable {
        let windowID: WindowID
        let animated: Bool
    }

    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var selectedWindowID: WindowID?
    @Published private(set) var scrollRequest: ScrollRequest?
    @Published private(set) var mode: SwitcherMode = .recent
    @Published private(set) var isVisible = false
    @Published var query = "" {
        didSet { rebuildResults(preserveSelection: false) }
    }

    var selectedResult: SearchResult? {
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
        case .search: "WINDOW SEARCH"
        case .fastSearch: "FAST SEARCH"
        }
    }

    private let repository: any WindowRepositoryProtocol
    private let learnedSearch: LearnedSearchStore
    private var allWindows: [WindowItem] = []
    private var cancellables: Set<AnyCancellable> = []
    private var pointerAnchor: CGPoint?
    private let pointerJitterThreshold: CGFloat = 2
    var onVisibilityChange: ((Bool) -> Void)?
    var onWillCommit: (() -> Void)?

    init(repository: any WindowRepositoryProtocol, learnedSearch: LearnedSearchStore) {
        self.repository = repository
        self.learnedSearch = learnedSearch
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
        self.mode = mode
        query = ""
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

    func appendToQuery(_ value: String) {
        guard value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return }
        if mode == .recent || isApplicationMode {
            mode = .search
        }
        query.append(contentsOf: value)
    }

    func beginSearch() {
        mode = .search
        query = ""
    }

    func deleteBackward() {
        guard !query.isEmpty else { return }
        query.removeLast()
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let index = ((selectedIndex + offset) % results.count + results.count) % results.count
        setSelection(results[index].item.id)
        scrollRequest = ScrollRequest(windowID: results[index].item.id, animated: true)
    }

    func handlePointerHover(over id: WindowID, at point: CGPoint) {
        guard isVisible, results.contains(where: { $0.item.id == id }) else { return }
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

    private func commit(_ result: SearchResult?) {
        guard isVisible else { return }
        onWillCommit?()
        guard let result else {
            dismiss()
            return
        }
        if !query.isEmpty {
            learnedSearch.learn(query: query, identity: result.item.searchIdentity)
        }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [repository] in
            repository.activate(result.item)
        }
    }

    func dismiss() {
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

    private var isApplicationMode: Bool {
        if case .application = mode { return true }
        return false
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

        if query.isEmpty {
            results = source.map {
                SearchResult(item: $0, score: 0, matchedTitleIndices: [], matchedAppIndices: [])
            }
        } else {
            results = source.compactMap { item in
                let appMatch = FuzzyMatcher.match(query: query, candidate: item.appName)
                let titleMatch = FuzzyMatcher.match(query: query, candidate: item.title)
                let contextMatch = item.context.flatMap { FuzzyMatcher.match(query: query, candidate: $0) }
                let combinedMatch = FuzzyMatcher.match(
                    query: query,
                    candidate: "\(item.appName) \(item.title) \(item.context ?? "")"
                )
                guard appMatch != nil || titleMatch != nil || contextMatch != nil || combinedMatch != nil else { return nil }

                let baseScore = max(
                    appMatch?.score ?? -.infinity,
                    titleMatch?.score ?? -.infinity,
                    contextMatch?.score ?? -.infinity,
                    combinedMatch?.score ?? -.infinity
                )
                return SearchResult(
                    item: item,
                    score: baseScore + learnedSearch.boost(for: query, identity: item.searchIdentity),
                    matchedTitleIndices: titleMatch?.indices ?? [],
                    matchedAppIndices: appMatch?.indices ?? []
                )
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.item.lastActive != $1.item.lastActive { return $0.item.lastActive > $1.item.lastActive }
                return $0.item.appName.localizedStandardCompare($1.item.appName) == .orderedAscending
            }
        }

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
