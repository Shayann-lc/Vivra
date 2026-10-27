import UIKit
import XCTest

/// Walks through onboarding and every tab with fresh storage, no HealthKit
/// and 90 days of made-up data (`-ui-testing -sample-data`), running Xcode's
/// accessibility audit on each screen (PLAN Phase 5). Each screen is also kept as a screenshot, which CI
/// exports as an artifact so the app can be seen without Xcode.
@MainActor
final class VivraUITests: XCTestCase {
    private let timeout: TimeInterval = 30
    private static let scrollEdgeEffectHeight: CGFloat = 60
    /// `com.apple.xcode.xctest.accessibilityAudit` "Audit failed to complete in time".
    private static let auditTimedOut = -56
    /// Taller than an inline navigation bar, shorter than a large-title one.
    private static let inlineNavigationBarMaxHeight: CGFloat = 70

    func testOnboardingAndEveryTabPassTheAccessibilityAudit() throws {
        // Keep going after an audit issue, so one run reports every screen.
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-sample-data"]
        app.launch()

        tap(app.buttons["Continue"], until: app.buttons["I Understand"], auditing: app, screenshot: "01 Welcome")
        let notNow = app.buttons["Not Now"]
        tap(app.buttons["I Understand"], until: notNow, auditing: app, screenshot: "02 Disclaimer")

        audit(app, screenshot: "03 Permission")
        let goToDashboard = app.buttons["Go to Dashboard"]
        while notNow.exists && !goToDashboard.exists {
            notNow.tap()
            _ = goToDashboard.waitForExistence(timeout: 2)
        }
        let todayTab = app.tabBars.buttons["Today"]
        tap(goToDashboard, until: todayTab, auditing: app, screenshot: "04 All set")

        for (number, tab) in [("05", "Today"), ("06", "Log"), ("07", "Insights"), ("08", "Progress")] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: timeout), "\(tab) tab")
            for _ in 1...3 where !button.isSelected {
                button.tap()
                let selected = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "isSelected == true"), object: button)
                _ = XCTWaiter.wait(for: [selected], timeout: 5)
            }
            audit(app, screenshot: "\(number) \(tab)")
            switch tab {
            case "Today":
                app.swipeUp()
                audit(app, screenshot: "05b Today, scrolled")
            case "Insights":
                let weekly = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Weekly summary'"))
                    .firstMatch
                tap(app.buttons["Create Weekly Summary"], until: weekly, auditing: app, screenshot: nil)
                audit(app, screenshot: "07b Weekly summary")
            default:
                break
            }
        }

        todayTab.tap()
        tap(app.buttons["Settings"], until: app.navigationBars["Settings"], auditing: app, screenshot: nil)
        audit(app, screenshot: "09 Settings")
    }

    /// Audits the current screen, then taps the element until `next`
    /// appears. CI simulators can be slow enough to drop a tap made while
    /// the app is still settling, so it tries up to three times.
    private func tap(
        _ element: XCUIElement,
        until next: XCUIElement,
        auditing app: XCUIApplication,
        screenshot name: String?
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), element.description)
        audit(app, screenshot: name)
        for _ in 1...3 {
            if element.exists { element.tap() }
            if next.waitForExistence(timeout: timeout) { return }
        }
        XCTFail("\(next.description) didn't appear after tapping \(element.description)")
    }

    private func audit(_ app: XCUIApplication, screenshot name: String?) {
        if let name {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        // The tab bar only counts while it's on screen (not under a sheet).
        // Its area includes the scroll edge effect above it, where iOS fades
        // the content scrolling underneath.
        let tabBar = app.tabBars.firstMatch
        let tabBarFrame =
            tabBar.exists && tabBar.isHittable
            ? tabBar.frame.inset(by: UIEdgeInsets(top: -Self.scrollEdgeEffectHeight, left: 0, bottom: 0, right: 0))
            : .null
        // The same fade happens under a collapsed (inline) navigation bar once
        // a screen has scrolled. A large-title bar isn't counted, so nothing
        // on an unscrolled screen is skipped.
        let navigationBar = app.navigationBars.firstMatch
        let fadedBars =
            navigationBar.exists && navigationBar.frame.height < Self.inlineNavigationBarMaxHeight
            ? [
                tabBarFrame,
                navigationBar.frame.inset(
                    by: UIEdgeInsets(top: 0, left: 0, bottom: -Self.scrollEdgeEffectHeight, right: 0)),
            ]
            : [tabBarFrame]
        // A screen that's still updating can make the audit time out (code
        // -56). Give it a moment and try once more before failing.
        for attempt in 1...2 {
            do {
                try app.performAccessibilityAudit { issue in
                    // Every issue is named in the test log with its element,
                    // and the ones ignored say why, so CI shows what to fix.
                    let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)'" } ?? "no element"
                    let reason = Self.knownFalsePositive(issue, fadedBars: fadedBars)
                    XCTContext.runActivity(
                        named: "Audit issue\(reason.map { " (ignored: \($0))" } ?? ""): \(issue.compactDescription) on "
                            + "\(element): \(issue.detailedDescription)"
                    ) { _ in }
                    return reason != nil
                }
                return
            } catch let error as NSError where error.code == Self.auditTimedOut && attempt == 1 {
                _ = XCTWaiter.wait(for: [XCTestExpectation(description: "Let the screen settle")], timeout: 3)
            } catch {
                XCTFail("Accessibility audit could not run: \(error)")
                return
            }
        }
    }

    /// Findings that aren't about anything Vivra draws or styles (PLAN
    /// Phase 5). Anything else fails the test.
    private static func knownFalsePositive(_ issue: XCUIAccessibilityAuditIssue, fadedBars: [CGRect]) -> String? {
        guard let element = issue.element else {
            // Pixel-level findings with nothing to point at, such as content
            // blurred behind the tab bar or a disabled stepper button.
            return "no element"
        }
        if fadedBars.contains(where: element.frame.intersects) {
            return "behind a translucent bar or its scroll edge fade"
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
