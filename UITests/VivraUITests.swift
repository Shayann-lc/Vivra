import XCTest

/// Walks through onboarding and every tab with fresh storage and no
/// HealthKit (`-ui-testing`), running Xcode's accessibility audit on each
/// screen (PLAN Phase 5).
@MainActor
final class VivraUITests: XCTestCase {
    private let timeout: TimeInterval = 20

    func testOnboardingAndEveryTabPassTheAccessibilityAudit() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        tap(app.buttons["Continue"], auditing: app)
        tap(app.buttons["I Understand"], auditing: app)

        let notNow = app.buttons["Not Now"]
        XCTAssertTrue(notNow.waitForExistence(timeout: timeout))
        audit(app)
        let goToDashboard = app.buttons["Go to Dashboard"]
        while notNow.exists && !goToDashboard.exists {
            notNow.tap()
            _ = goToDashboard.waitForExistence(timeout: 1)
        }
        tap(goToDashboard, auditing: app)

        for tab in ["Today", "Log", "Insights", "Progress"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: timeout), "\(tab) tab")
            button.tap()
            audit(app)
        }

        app.tabBars.buttons["Today"].tap()
        tap(app.buttons["Settings"], auditing: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: timeout))
        audit(app)
    }

    /// Audits the current screen, then taps the element.
    private func tap(_ element: XCUIElement, auditing app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), element.description)
        audit(app)
        element.tap()
    }

    private func audit(_ app: XCUIApplication) {
        do {
            try app.performAccessibilityAudit()
        } catch {
            XCTFail("Accessibility audit could not run: \(error)")
        }
    }
}
