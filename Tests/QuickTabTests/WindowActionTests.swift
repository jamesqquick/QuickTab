import XCTest
@testable import QuickTab

final class WindowActionTests: XCTestCase {
    func testCloseAndQuitAcceptAmbiguousReportedFailure() {
        XCTAssertTrue(WindowAction.close.isAccepted(reportedSuccess: false))
        XCTAssertTrue(WindowAction.quitApplication.isAccepted(reportedSuccess: false))
    }

    func testMinimizeAndHideRequireReportedSuccess() {
        XCTAssertFalse(WindowAction.minimize.isAccepted(reportedSuccess: false))
        XCTAssertFalse(WindowAction.hideApplication.isAccepted(reportedSuccess: false))
        XCTAssertTrue(WindowAction.minimize.isAccepted(reportedSuccess: true))
        XCTAssertTrue(WindowAction.hideApplication.isAccepted(reportedSuccess: true))
    }
}
