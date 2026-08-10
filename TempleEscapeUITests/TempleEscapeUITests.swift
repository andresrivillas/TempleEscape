import XCTest

/// UI tests for Temple Escape: menu flow → start run → in-game HUD appears.
final class TempleEscapeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMenuShowsTitleAndStartButton() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["TEMPLE ESCAPE"].waitForExistence(timeout: 8),
                      "Menu title should appear")
        XCTAssertTrue(app.buttons["START RUN"].exists, "Start button should exist")
    }

    func testStartRunShowsHUD() {
        let app = XCUIApplication()
        app.launch()

        let start = app.buttons["START RUN"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()

        // In the running phase a score pill like "7 m" appears (mountain icon).
        let scoreText = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "\\d+ m")
        ).firstMatch
        XCTAssertTrue(scoreText.waitForExistence(timeout: 8),
                      "Score HUD should appear after starting a run")
    }

    func testRunEndsInGameOverScreen() {
        let app = XCUIApplication()
        // -autostart skips the menu; the AI-runner always crashes eventually.
        app.launchArguments = ["-autostart"]
        app.launch()

        // The bot never dodges, so it dies within a few seconds.
        XCTAssertTrue(app.staticTexts["CRUSHED!"].waitForExistence(timeout: 30),
                      "Game over screen should appear")
        XCTAssertTrue(app.buttons["RUN AGAIN"].exists, "Run again button should exist")
    }

    func testSwipeUpMakesPlayerJump() {
        let app = XCUIApplication()
        app.launchArguments = ["-autostart"]
        app.launch()

        let height = app.staticTexts["debugPlayerY"]
        let jumpLabel = app.staticTexts["debugJumpCount"]
        XCTAssertTrue(height.waitForExistence(timeout: 8), "Debug height label should exist")

        // Swipe up to trigger a jump. The synthesized swipe occasionally gets
        // dropped by the simulator under load, so retry a few times (consecutive
        // jumps are harmless while grounded).
        var jumpCount = 0
        var maxY = 0.0
        for _ in 0..<3 where !(jumpCount > 0 && maxY > 0.4) {
            app.swipeUp()
            let deadline = Date().addingTimeInterval(0.9)
            while Date() < deadline {
                if jumpLabel.exists, let v = Int(jumpLabel.label) {
                    jumpCount = max(jumpCount, v)
                }
                if height.exists, let v = Double(height.label) {
                    maxY = max(maxY, v)
                }
                if jumpCount > 0 && maxY > 0.4 { break }
                usleep(50_000)
            }
        }
        print("JUMP-DEBUG jumps=\(jumpCount) maxY=\(maxY)")
        XCTAssertGreaterThan(jumpCount, 0, "The swipe should trigger a jump")
        XCTAssertGreaterThan(maxY, 0.4,
                             "Swipe up should lift the player ~1.7 m (saw maxY=\(maxY))")
    }

    func testCollectsCoinsInCenterLane() {
        let app = XCUIApplication()
        // -debugcoins guarantees a coin line straight ahead in the center lane.
        app.launchArguments = ["-autostart", "-debugcoins"]
        app.launch()

        let gems = app.staticTexts["hudGems"]
        XCTAssertTrue(gems.waitForExistence(timeout: 8), "Gem counter should exist")
        let gotCoins = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label.intValue > 0"),
            object: gems
        )
        XCTAssertEqual(XCTWaiter.wait(for: [gotCoins], timeout: 10), .completed,
                       "Running through the coin line should increment the gem counter")
    }
}
