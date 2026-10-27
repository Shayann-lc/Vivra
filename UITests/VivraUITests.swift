import XCTest

/// Walks through onboarding and every tab with fresh storage and no
/// HealthKit (`-ui-testing`), running Xcode's accessibility audit on each
/// screen (PLAN Phase 5). Each screen is also kept as a screenshot, which CI
/// exports as an artifact so the app can be seen without Xcode.
@MainActor
final class VivraUITests: XCTestCase {
    private let timeout: TimeInterval = 20

    func testOnboardingAndEveryTabPassTheAccessibilityAudit() throws {
        // Keep going after an audit issue, so one run reports every screen.
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        tap(app.buttons["Continue"], auditing: app, screenshot: "01 Welcome")
        tap(app.buttons["I Understand"], auditing: app, screenshot: "02 Disclaimer")

        let notNow = app.buttons["Not Now"]
        XCTAssertTrue(notNow.waitForExistence(timeout: timeout))
        audit(app, screenshot: "03 Permission")
        let goToDashboard = app.buttons["Go to Dashboard"]
        while notNow.exists && !goToDashboard.exists {
            notNow.tap()
            _ = goToDashboard.waitForExistence(timeout: 1)
        }
        tap(goToDashboard, auditing: app, screenshot: "04 All set")

        for (number, tab) in [("05", "Today"), ("06", "Log"), ("07", "Insights"), ("08", "Progress")] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: timeout), "\(tab) tab")
            button.tap()
            audit(app, screenshot: "\(number) \(tab)")
        }

        app.tabBars.buttons["Today"].tap()
        tap(app.buttons["Settings"], auditing: app, screenshot: nil)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: timeout))
        audit(app, screenshot: "09 Settings")
    }

    /// Audits the current screen, then taps the element.
    private func tap(_ element: XCUIElement, auditing app: XCUIApplication, screenshot name: String?) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), element.description)
        audit(app, screenshot: name)
        element.tap()
    }

    private func audit(_ app: XCUIApplication, screenshot name: String?) {
        if let name {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        do {
            try app.performAccessibilityAudit { issue in
                // Each issue is named in the test log with its element, so
                // CI shows exactly what to fix.
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)'" } ?? "no element"
                XCTContext.runActivity(
                    named: "Audit issue: \(issue.compactDescription) on \(element): \(issue.detailedDescription)"
                ) { _ in }
                return false
            }
        } catch {
            XCTFail("Accessibility audit could not run: \(error)")
        }
    }
}
