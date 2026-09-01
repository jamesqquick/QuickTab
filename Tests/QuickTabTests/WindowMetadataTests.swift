import XCTest
@testable import QuickTab

final class WindowMetadataTests: XCTestCase {
    func testFormatsBrowserURLWithoutProtocolOrQuery() {
        XCTAssertEqual(
            WindowMetadata.contextLabel(
                "https://www.example.com/docs/getting-started?source=nav",
                title: "Getting Started"
            ),
            "example.com/docs/getting-started"
        )
    }

    func testCompactsFileURLToParentAndFilename() {
        XCTAssertEqual(
            WindowMetadata.contextLabel(
                "file:///Users/james/Projects/QuickTab/Sources/App.swift",
                title: "App.swift"
            ),
            "Sources/App.swift"
        )
    }

    func testOmitsGenericDescriptions() {
        XCTAssertNil(WindowMetadata.contextLabel("standard window", title: "Untitled"))
    }
}
