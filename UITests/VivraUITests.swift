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
        completeOnboarding(app, audited: true)
        let todayTab = tabButton("Today", in: app)

        for (number, tab) in [("05", "Today"), ("06", "Log"), ("07", "Insights"), ("08", "Progress")] {
            let button = tabButton(tab, in: app)
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
                connections(app)
                let weekly = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Weekly summary'"))
                    .firstMatch
                // Today's automatic check-in sits above it, so on short
                // screens the button starts below the fold.
                let createWeekly = app.buttons["Create Weekly Summary"]
                reveal(createWeekly, in: app)
                tap(createWeekly, until: weekly, auditing: app, screenshot: nil)
                // Insights greys out its buttons and shows "Writing…" while a
                // report is being made, and the new summary fades in. Audit
                // once that's over. (The summary can push the button itself
                // off screen, so it's the progress label that's watched.)
                let writing = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS 'Writing'")).firstMatch
                let finished = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "exists == false"), object: writing)
                XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: timeout), .completed, "Weekly summary written")
                _ = XCTWaiter.wait(
                    for: [XCTestExpectation(description: "Let the summary finish appearing")], timeout: 2)
                audit(app, screenshot: "07b Weekly summary")
            default:
                break
            }
        }

        todayTab.tap()
        tap(app.buttons["Settings"], until: app.navigationBars["Settings"], auditing: app, screenshot: nil)
        audit(app, screenshot: "09 Settings")
    }

    /// Connections at one of the largest text sizes, where rows stack and
    /// the pickers become menus.
    func testConnectionsAtALargeTextSize() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-sample-data", "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityL",
        ]
        app.launch()
        completeOnboarding(app, audited: false)
        let insights = tabButton("Insights", in: app)
        XCTAssertTrue(insights.waitForExistence(timeout: timeout), "Insights tab")
        for _ in 1...3 where !insights.isSelected {
            insights.tap()
            _ = XCTWaiter.wait(
                for: [
                    XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: insights)
                ],
                timeout: 5)
        }
        audit(app, screenshot: "10 Connections, larger text")
    }

    /// Connections (PLAN Phase 7): by outcome (audited above as "07"), by
    /// habit, one connection's detail, then back to Summaries.
    private func connections(_ app: XCUIApplication) {
        let byHabit = app.buttons["By Habit"]
        XCTAssertTrue(byHabit.waitForExistence(timeout: timeout), "By Habit")
        byHabit.tap()
        audit(app, screenshot: "07c Connections, by habit")

        // A found connection's label is its full sentence ("…: with none, a
        // median of …"); rows with nothing to show aren't links.
        let found = app.buttons.matching(NSPredicate(format: "label CONTAINS ': with '")).firstMatch
        reveal(found, in: app)
        let detail = app.navigationBars["Connection"]
        // The list was just audited by habit; auditing again mid-scroll can
        // time out on a slow simulator.
        tap(found, until: detail, auditing: nil, screenshot: nil)
        audit(app, screenshot: "07d Connection detail")
        app.swipeUp()
        audit(app, screenshot: "07e Connection detail, scrolled")
        // Back to the top so the navigation bar shows again (iOS 27 can hide
        // it once scrolled), then back; the edge swipe is the fallback.
        app.swipeDown()
        app.swipeDown()
        let back = app.navigationBars.buttons.firstMatch
        if back.waitForExistence(timeout: 5) {
            back.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        }

        let summaries = app.buttons["Summaries"]
        for _ in 0..<8 where !(summaries.exists && summaries.isHittable) { app.swipeDown() }
        tap(summaries, until: app.buttons["Why do I feel off today?"], auditing: app, screenshot: nil)
    }

    /// Onboarding, audited and kept as screenshots unless `audited` is off.
    private func completeOnboarding(_ app: XCUIApplication, audited: Bool) {
        let auditing = audited ? app : nil
        tap(app.buttons["Continue"], until: app.buttons["I Understand"], auditing: auditing, screenshot: "01 Welcome")
        let notNow = app.buttons["Not Now"]
        tap(app.buttons["I Understand"], until: notNow, auditing: auditing, screenshot: "02 Disclaimer")

        if audited { audit(app, screenshot: "03 Permission") }
        let goToDashboard = app.buttons["Go to Dashboard"]
        while notNow.exists && !goToDashboard.exists {
            notNow.tap()
            _ = goToDashboard.waitForExistence(timeout: 2)
        }
        tap(goToDashboard, until: tabButton("Today", in: app), auditing: auditing, screenshot: "04 All set")
    }

    /// Scrolls until `element` is on screen. Lists only create rows near the
    /// visible area, so an element further down doesn't exist until then.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
    }

    /// A tab's button wherever the system puts the tabs: a bottom tab bar on
    /// most iPhones, or a floating side bar on wide ones (iOS 27), which
    /// isn't reported as a tab bar.
    private func tabButton(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    /// Audits the current screen (unless `app` is nil), then taps the
    /// element until `next` appears. CI simulators can be slow enough to drop a tap made while
    /// the app is still settling, so it tries up to three times.
    private func tap(
        _ element: XCUIElement,
        until next: XCUIElement,
        auditing app: XCUIApplication?,
        screenshot name: String?
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), element.description)
        if let app { audit(app, screenshot: name) }
        for _ in 1...3 {
            if element.exists { element.tap() }
            if next.waitForExistence(timeout: timeout) { return }
        }
        XCTFail("\(next.description) didn't appear after tapping \(element.description)")
    }

    private func audit(_ app: XCUIApplication, screenshot name: String?) {
        if let name {
            // Screenshots are only for people to look at. A slow simulator
            // can time out taking one, which mustn't fail the audit.
            let bestEffort = XCTExpectedFailure.Options()
            bestEffort.isStrict = false
            XCTExpectFailure("Screenshots are best-effort", options: bestEffort) {
                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        // The tab bar only counts while it's on screen (not under a sheet).
        // Its area includes the scroll edge effect above it, where iOS fades
        // the content scrolling underneath.
        let tabBar = app.tabBars.firstMatch
        let tabBarFrame =
            tabBar.exists && tabBar.isHittable
            ? tabBar.frame.inset(by: UIEdgeInsets(top: -Self.scrollEdgeEffectHeight, left: 0, bottom: 0, right: 0))
            : .null
        // The same fade happens at the top of a scrolled screen: under the
        // status bar and a collapsed (inline) navigation bar, and just below
        // it. A large-title bar isn't counted, so nothing on an unscrolled
        // screen is skipped.
        // Without a bottom tab bar (the floating side bar on wide iPhones),
        // the fade is at the screen's bottom edge, which also takes in rows
        // the list has made just below the screen.
        let window = app.windows.firstMatch.frame
        let bottomEdge =
            tabBarFrame.isNull && !window.isEmpty
            ? CGRect(
                x: -10_000, y: window.maxY - Self.scrollEdgeEffectHeight, width: 20_000,
                height: 10_000 + Self.scrollEdgeEffectHeight)
            : .null
        let navigationBar = app.navigationBars.firstMatch
        let fadedBars =
            navigationBar.exists && navigationBar.frame.height < Self.inlineNavigationBarMaxHeight
            ? [
                tabBarFrame,
                bottomEdge,
                // Everything above the bar's bottom edge plus the fade,
                // including content scrolled off the top of the screen.
                CGRect(
                    x: -10_000, y: -10_000, width: 20_000,
                    height: 10_000 + navigationBar.frame.maxY + Self.scrollEdgeEffectHeight),
            ]
            : [tabBarFrame, bottomEdge]
        // The text size checks briefly enlarge the text, which reflows a
        // scrolled list and moves it. Contrast is measured first, on the
        // screen as it was, and the text size checks run afterwards.
        let textSizeChecks: XCUIAccessibilityAuditType = [.dynamicType, .textClipped]
        for types in [XCUIAccessibilityAuditType.all.subtracting(textSizeChecks), textSizeChecks] {
            audit(app, for: types, fadedBars: fadedBars)
        }
    }

    private func audit(_ app: XCUIApplication, for types: XCUIAccessibilityAuditType, fadedBars: [CGRect]) {
        // A screen that's still updating can make the audit time out (code
        // -56). Give it a moment and try once more before failing.
        for attempt in 1...2 {
            do {
                try app.performAccessibilityAudit(for: types) { issue in
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
