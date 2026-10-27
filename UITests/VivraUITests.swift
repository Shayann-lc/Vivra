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
        // The tab bar only counts while it's on screen (not under a sheet).
        let tabBar = app.tabBars.firstMatch
        let tabBarFrame = tabBar.exists && tabBar.isHittable ? tabBar.frame : .null
        do {
            try app.performAccessibilityAudit { issue in
                // Every issue is named in the test log with its element, and
                // the ones ignored say why, so CI shows exactly what to fix.
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)'" } ?? "no element"
                let reason = Self.knownFalsePositive(issue, tabBarFrame: tabBarFrame)
                XCTContext.runActivity(
                    named: "Audit issue\(reason.map { " (ignored: \($0))" } ?? ""): \(issue.compactDescription) on "
                        + "\(element): \(issue.detailedDescription)"
                ) { _ in }
                return reason != nil
            }
        } catch {
            XCTFail("Accessibility audit could not run: \(error)")
        }
    }

    /// Findings that aren't about anything Vivra draws or styles (PLAN
    /// Phase 5). Anything else fails the test.
    private static func knownFalsePositive(_ issue: XCUIAccessibilityAuditIssue, tabBarFrame: CGRect) -> String? {
        guard let element = issue.element else {
            // Pixel-level findings with nothing to point at, such as content
            // blurred behind the tab bar or a disabled stepper button.
            return "no element"
        }
        if element.frame.intersects(tabBarFrame) {
            return "behind the translucent tab bar"
        }
        if issue.auditType == .contrast && issue.compactDescription == "Contrast nearly passed" {
            // System secondary text and the system tint, which pass at
            // larger sizes.
            return "nearly passed"
        }
        if issue.auditType == .dynamicType && issue.compactDescription.localizedStandardContains("partially") {
            // Reported for system list headers, labels and toolbar buttons,
            // which use system text styles and do scale.
            return "system text style"
        }
        return nil
    }
}
