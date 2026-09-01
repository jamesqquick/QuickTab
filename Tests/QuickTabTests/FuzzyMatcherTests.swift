import XCTest
@testable import QuickTab

final class FuzzyMatcherTests: XCTestCase {
    func testMatchesNonConsecutiveCharacters() {
        let match = FuzzyMatcher.match(query: "ctx", candidate: "Contexts")
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.indices, IndexSet([0, 3, 5]))
    }

    func testWordStartsOutrankInteriorCharacters() throws {
        let acronym = try XCTUnwrap(FuzzyMatcher.match(query: "qd", candidate: "Quick Draft"))
        let interior = try XCTUnwrap(FuzzyMatcher.match(query: "qd", candidate: "Acquired"))
        XCTAssertGreaterThan(acronym.score, interior.score)
    }

    func testConsecutiveMatchesGainWeightForLongerQuery() throws {
        let consecutive = try XCTUnwrap(FuzzyMatcher.match(query: "term", candidate: "Terminal"))
        let sparse = try XCTUnwrap(FuzzyMatcher.match(query: "term", candidate: "Text Editor Room Manager"))
        XCTAssertGreaterThan(consecutive.score, sparse.score)
    }

    func testOneMismatchCanBeAllowed() {
        XCTAssertNotNil(FuzzyMatcher.match(query: "safxri", candidate: "Safari", allowMismatch: true))
        XCTAssertNil(FuzzyMatcher.match(query: "safxri", candidate: "Safari", allowMismatch: false))
    }

    @MainActor
    func testLearnedShortcutPersistsBySemanticIdentity() {
        let suiteName = "QuickTabTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstStore = LearnedSearchStore(defaults: defaults)
        firstStore.learn(query: "s", identity: "com.apple.Safari|Start Page")

        let reloadedStore = LearnedSearchStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.boost(for: "S", identity: "com.apple.Safari|Start Page"), 10_000)
        XCTAssertEqual(reloadedStore.boost(for: "s", identity: "com.apple.Safari|Other Tab"), 0)
    }
}
