import XCTest
@testable import TempleEscape

/// Unit tests for the pure gameplay rules (no SceneKit needed).
final class TempleRulesTests: XCTestCase {

    func testSpeedRampsWithDistance() {
        XCTAssertEqual(TempleRules.speed(forDistance: 0), 7.2, accuracy: 0.001)
        XCTAssertGreaterThan(TempleRules.speed(forDistance: 100), TempleRules.speed(forDistance: 0))
        XCTAssertGreaterThan(TempleRules.speed(forDistance: 200), TempleRules.speed(forDistance: 100))
    }

    func testSpeedCapsAtMaximum() {
        // The ramp must never exceed the cap, no matter the distance.
        for d: Float in [0, 10, 100, 1000, 100_000, 1_000_000] {
            XCTAssertLessThanOrEqual(TempleRules.speed(forDistance: d), 15.5)
        }
        XCTAssertEqual(TempleRules.speed(forDistance: 100_000), 15.5, accuracy: 0.001)
    }

    func testBoulderWaitsBehindCamera() {
        // During play the boulder must sit behind the chase camera (z ≈ 5.4),
        // out of frame, until the player crashes.
        XCTAssertGreaterThan(TempleRules.boulderChaseZ, 6.0, "boulder must be behind the camera")
        XCTAssertLessThan(TempleRules.boulderChaseZ, 12.0, "boulder must not be too far away")
        XCTAssertGreaterThan(TempleRules.boulderChaseZ - TempleRules.boulderRadius, 5.4,
                            "boulder must not poke into the camera view")
        // On death it must run OVER the player: end well in front (negative z).
        XCTAssertLessThan(TempleRules.boulderSmashZ, -2.0, "boulder must end past the player")
        XCTAssertGreaterThan(TempleRules.boulderRadius, 0.5)
    }

    func testScoreIsIntegerMeters() {
        XCTAssertEqual(TempleRules.score(forDistance: 0), 0)
        XCTAssertEqual(TempleRules.score(forDistance: 42.7), 42)
        XCTAssertEqual(TempleRules.score(forDistance: 999.999), 999)
    }

    func testLaneClamping() {
        XCTAssertEqual(TempleRules.clampedLane(-1), 0)
        XCTAssertEqual(TempleRules.clampedLane(0), 0)
        XCTAssertEqual(TempleRules.clampedLane(1), 1)
        XCTAssertEqual(TempleRules.clampedLane(2), 2)
        XCTAssertEqual(TempleRules.clampedLane(3), 2)
        XCTAssertEqual(TempleRules.clampedLane(99), 2)
    }

    func testJumpImpulseGivesSensibleApex() {
        // h = v² / 2g with v = impulse (mass 1): should be ≈ 1.7 m.
        let apex = TempleRules.jumpImpulse * TempleRules.jumpImpulse / (2 * abs(TempleRules.gravity))
        XCTAssertEqual(apex, 1.77, accuracy: 0.1)
    }

    func testThreeDistinctLanes() {
        let lanes = TempleRules.lanes
        XCTAssertEqual(lanes.count, 3)
        XCTAssertEqual(Set(lanes.map { $0 }), Set([-1.25, 0, 1.25]))
    }

    func testShouldLandOnGround() {
        // Resting on the ground with no upward velocity → land.
        XCTAssertTrue(TempleRules.shouldLand(playerY: 0, velocityY: 0))
        XCTAssertTrue(TempleRules.shouldLand(playerY: 0.01, velocityY: -0.05))
    }

    func testShouldNotLandWhileRising() {
        // Just after a jump the body is still at y = 0 for one frame but has
        // strong upward velocity — that must NOT be treated as landing.
        XCTAssertFalse(TempleRules.shouldLand(playerY: 0, velocityY: TempleRules.jumpImpulse))
        XCTAssertFalse(TempleRules.shouldLand(playerY: 0, velocityY: 5.0))
        XCTAssertFalse(TempleRules.shouldLand(playerY: 0.5, velocityY: -3))
    }

    func testShouldNotLandFallingAboveGround() {
        XCTAssertFalse(TempleRules.shouldLand(playerY: 0.2, velocityY: -1))
    }

    // MARK: Manual jump integrator

    func testGroundedJumpDoesNotMove() {
        let m = TempleRules.advanceJump(TempleRules.JumpMotion(), dt: 1 / 60)
        XCTAssertEqual(m, TempleRules.JumpMotion())
        XCTAssertTrue(m.grounded)
    }

    func testJumpReachesExpectedApex() {
        // h = v²/2g with v = 5.9 → ≈ 1.78 m. Simulate the full jump at 60 fps.
        var m = TempleRules.JumpMotion(y: 0, vy: TempleRules.jumpImpulse, grounded: false)
        var apex: Float = 0
        var steps = 0
        while !m.grounded && steps < 500 {
            m = TempleRules.advanceJump(m, dt: 1 / 60)
            apex = max(apex, m.y)
            steps += 1
        }
        XCTAssertEqual(apex, 1.78, accuracy: 0.1)
        XCTAssertTrue(m.grounded, "jump must land")
        XCTAssertEqual(m.y, 0, accuracy: 0.001)
        XCTAssertEqual(m.vy, 0, accuracy: 0.001)
    }

    func testJumpDurationIsSensible() {
        // Total air time ≈ 2·v/g ≈ 1.2 s.
        var m = TempleRules.JumpMotion(y: 0, vy: TempleRules.jumpImpulse, grounded: false)
        var steps = 0
        while !m.grounded && steps < 500 {
            m = TempleRules.advanceJump(m, dt: 1 / 60)
            steps += 1
        }
        let seconds = Double(steps) / 60.0
        XCTAssertEqual(seconds, 1.2, accuracy: 0.15)
    }
}
