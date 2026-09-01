import AppKit
import Combine

@MainActor
final class SwitcherViewModel: ObservableObject {
    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var selectedIndex = 0
    @Published private(set) var mode: SwitcherMode = .recent
    @Published private(set) var isVisible = false
    @Published var query = "" {
        didSet { rebuildResults(preserveSelection: false) }
    }

    var selectedResult: SearchResult? {
        guard results.indices.contains(selectedIndex) else { return nil }
        return results[selectedIndex]
    }

    var modeLabel: String {
        switch mode {
        case .recent: "RECENT WINDOWS"
        case .application: "CURRENT APP"
        case .search: "WINDOW SEARCH"
        case .fastSearch: "FAST SEARCH"
        }
    }

    private let repository: WindowRepository
    private let learnedSearch: LearnedSearchStore
    private var allWindows: [WindowItem] = []
    private var cancellables: Set<AnyCancellable> = []
    var onVisibilityChange: ((Bool) -> Void)?
    var onWillCommit: (() -> Void)?

    init(repository: WindowRepository, learnedSearch: LearnedSearchStore) {
        self.repository = repository
        self.learnedSearch = learnedSearch
        repository.$windows
            .sink { [weak self] windows in
                guard let self else { return }
                self.allWindows = windows
                self.rebuildResults(preserveSelection: true)
            }
            .store(in: &cancellables)
    }

    func present(_ mode: SwitcherMode, advanceImmediately: Bool = false) {
        self.mode = mode
        query = ""
        isVisible = true
        rebuildResults(preserveSelection: false)
        if advanceImmediately, results.count > 1 {
            if let activeIndex = results.firstIndex(where: { $0.item.id == repository.activeWindowID }) {
                selectedIndex = (activeIndex + 1) % results.count
            } else {
                selectedIndex = 0
            }
        } else {
            selectedIndex = 0
        }
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
        selectedIndex = (selectedIndex + offset + results.count) % results.count
    }

    func select(_ index: Int) {
        guard results.indices.contains(index) else { return }
        selectedIndex = index
    }

    func commit() {
        guard isVisible else { return }
        onWillCommit?()
        guard let result = selectedResult else {
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
            let adjacentIndex = selectedIndex
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
        let selectedID = preserveSelection ? selectedResult?.item.id : nil
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

        if let selectedID, let updatedIndex = results.firstIndex(where: { $0.item.id == selectedID }) {
            selectedIndex = updatedIndex
        } else if results.isEmpty {
            selectedIndex = 0
        } else if let preferredIndex {
            selectedIndex = min(preferredIndex, results.count - 1)
        } else if !preserveSelection {
            selectedIndex = 0
        } else {
            selectedIndex = min(selectedIndex, results.count - 1)
        }
    }
}
