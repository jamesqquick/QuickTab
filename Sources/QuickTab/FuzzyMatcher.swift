import Foundation

struct FuzzyMatch {
    let score: Double
    let indices: IndexSet
}

enum FuzzyMatcher {
    static func match(query: String, candidate: String, allowMismatch: Bool = true) -> FuzzyMatch? {
        let query = normalizedCharacters(query)
        let candidate = normalizedCharacters(candidate)
        guard !query.isEmpty else { return FuzzyMatch(score: 0, indices: []) }
        guard !candidate.isEmpty else { return nil }

        var candidateIndex = 0
        var matched = IndexSet()
        var score = 0.0
        var mismatches = 0
        var previousMatch: Int?

        for queryCharacter in query {
            let searchStart = candidateIndex
            var foundIndex: Int?
            while candidateIndex < candidate.count {
                if candidate[candidateIndex] == queryCharacter {
                    foundIndex = candidateIndex
                    break
                }
                candidateIndex += 1
            }

            guard let index = foundIndex else {
                mismatches += 1
                if !allowMismatch || mismatches > 1 { return nil }
                candidateIndex = searchStart
                continue
            }

            matched.insert(index)
            let isWordStart = index == 0 || !candidate[index - 1].isLetter && !candidate[index - 1].isNumber
            score += isWordStart ? 18 : 7
            if let previousMatch, index == previousMatch + 1 { score += 10 }
            score += max(0, 5 - Double(index) * 0.15)
            previousMatch = index
            candidateIndex = index + 1
        }

        score -= Double(mismatches) * 14
        score -= Double(max(0, candidate.count - matched.count)) * 0.025
        return FuzzyMatch(score: score, indices: matched)
    }

    private static func normalizedCharacters(_ value: String) -> [Character] {
        Array(value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))
    }
}

@MainActor
final class LearnedSearchStore {
    private let defaults: UserDefaults
    private let key = "learnedSearchShortcuts"
    private(set) var shortcuts: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shortcuts = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    func boost(for query: String, identity: String) -> Double {
        shortcuts[normalize(query)] == identity ? 10_000 : 0
    }

    func learn(query: String, identity: String) {
        let query = normalize(query)
        guard !query.isEmpty, query.count <= 3 else { return }
        shortcuts[query] = identity
        defaults.set(shortcuts, forKey: key)
    }

    private func normalize(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
