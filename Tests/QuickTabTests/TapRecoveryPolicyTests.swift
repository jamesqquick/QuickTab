import XCTest
@testable import QuickTab

final class TapRecoveryPolicyTests: XCTestCase {
    func testFailedRecoveryRetriesOnceThenStops() {
        var policy = TapRecoveryPolicy()

        XCTAssertTrue(policy.requestRecovery())
        policy.beginAttempt()
        XCTAssertTrue(policy.recordFailedAttempt())
        XCTAssertEqual(policy.attemptCount, 1)

        policy.beginAttempt()
        XCTAssertFalse(policy.recordFailedAttempt())
        XCTAssertEqual(policy.attemptCount, 0)
        XCTAssertTrue(policy.requestRecovery())
    }

    func testDisableDuringCooldownWaitsThenRequestsRecovery() {
        var policy = TapRecoveryPolicy()

        XCTAssertTrue(policy.requestRecovery())
        policy.beginAttempt()
        XCTAssertFalse(policy.requestRecovery())
        XCTAssertTrue(policy.recoveryRequested)

        XCTAssertTrue(policy.finishCooldown())
        policy.beginAttempt()
        XCTAssertFalse(policy.recoveryRequested)
        XCTAssertEqual(policy.attemptCount, 2)
    }

    func testStableCooldownResetsAttemptBudget() {
        var policy = TapRecoveryPolicy()

        XCTAssertTrue(policy.requestRecovery())
        policy.beginAttempt()

        XCTAssertFalse(policy.finishCooldown())
        XCTAssertEqual(policy.attemptCount, 0)
        XCTAssertTrue(policy.requestRecovery())
    }

    func testThirdConsecutiveDisableExhaustsAutomaticRecovery() {
        var policy = TapRecoveryPolicy()

        XCTAssertTrue(policy.requestRecovery())
        policy.beginAttempt()
        XCTAssertFalse(policy.requestRecovery())
        XCTAssertTrue(policy.finishCooldown())
        policy.beginAttempt()
        XCTAssertFalse(policy.requestRecovery())

        XCTAssertFalse(policy.finishCooldown())
        XCTAssertEqual(policy.attemptCount, 0)
        XCTAssertTrue(policy.requestRecovery())
    }
}
