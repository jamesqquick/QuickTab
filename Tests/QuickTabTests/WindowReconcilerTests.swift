import AppKit
import XCTest
@testable import QuickTab

final class WindowReconcilerTests: XCTestCase {
    func testRetainsCachedWindowsMissingFromCurrentSpaceScan() {
        let currentSpace = window(fingerprint: "current", title: "Current Space")
        let otherSpace = window(fingerprint: "other", title: "Other Space")

        let result = WindowReconciler.merge(
            fresh: [currentSpace],
            cached: [otherSpace],
            shouldRetainCached: { _ in true }
        )

        XCTAssertEqual(result.map(\.title), ["Current Space", "Other Space"])
    }

    func testFreshWindowReplacesCachedWindowWithSameID() {
        let cached = window(fingerprint: "same", title: "Old Title")
        let fresh = window(fingerprint: "same", title: "New Title")

        let result = WindowReconciler.merge(
            fresh: [fresh],
            cached: [cached],
            shouldRetainCached: { _ in true }
        )

        XCTAssertEqual(result.map(\.title), ["New Title"])
    }

    func testDropsCachedWindowWhenElementIsInvalid() {
        let closed = window(fingerprint: "closed", title: "Closed")

        let result = WindowReconciler.merge(
            fresh: [],
            cached: [closed],
            shouldRetainCached: { _ in false }
        )

        XCTAssertTrue(result.isEmpty)
    }

    private func window(fingerprint: String, title: String) -> WindowItem {
        WindowItem(
            id: WindowID(processID: 42, fingerprint: fingerprint),
            processID: 42,
            appName: "Test App",
            bundleIdentifier: "com.example.test",
            title: title,
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
