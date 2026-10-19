//
//  FFishAsiaUITests.swift
//  FFishAsiaUITests
//
//  Created by PK on 2024/8/9.
//

import XCTest

final class FFishAsiaUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testCatalogFiltersAndPrimaryActions() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenOnboarding", "YES", "FFISH_SNAPSHOT_APP_LANGUAGE=en"]
        app.launch()

        let starter = app.buttons["model.35559c2236d04c1a80ccbe08cae863c6"]
        XCTAssertTrue(starter.waitForExistence(timeout: 10))
        capture("01-catalog", app: app)

        app.buttons["catalog.filter"].tap()
        app.buttons["Animated"].tap()
        XCTAssertTrue(starter.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["model.f5e6f5a985ea4fc2a14ee0b4b37572b5"].exists)
        capture("02-animated", app: app)

        starter.tap()
        XCTAssertTrue(app.buttons["Preview in 3D"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Preview in 3D"].isHittable)
        #if os(iOS)
        XCTAssertTrue(app.buttons["View in AR"].isHittable)
        #endif
        capture("03-detail-actions", app: app)
        app.buttons["Close"].tap()

        app.buttons["catalog.filter"].tap()
        app.buttons["Offline"].tap()
        XCTAssertTrue(starter.waitForExistence(timeout: 5))
        capture("04-offline", app: app)

        app.buttons["catalog.filter"].tap()
        app.buttons["All models"].tap()
        let search = app.textFields.firstMatch
        search.tap()
        search.typeText("no-such-specimen-123")
        XCTAssertFalse(starter.exists)
        app.buttons["Clear search"].tap()
        XCTAssertTrue(starter.waitForExistence(timeout: 5))
    }

    private func capture(_ name: String, app: XCUIApplication) {
        #if os(macOS)
        let sheet = app.sheets.firstMatch
        let attachment = XCTAttachment(screenshot: sheet.exists ? sheet.screenshot() : app.windows.firstMatch.screenshot())
        #else
        let attachment = XCTAttachment(screenshot: app.screenshot())
        #endif
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    #if os(macOS)
    func testMacCatalogAndDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenOnboarding", "YES", "FFISH_SNAPSHOT_APP_LANGUAGE=en"]
        app.launch()
        // macOS may restore a prior session without an open window.
        if !app.windows.firstMatch.waitForExistence(timeout: 5) {
            let fileMenu = app.menuBars.menuBarItems.containing(.menuItem, identifier: "menuAction:").firstMatch
            fileMenu.click()
            app.menuItems["menuAction:"].click()
        }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        app.activate()
        let starter = app.buttons["model.35559c2236d04c1a80ccbe08cae863c6"]
        XCTAssertTrue(starter.waitForExistence(timeout: 10))
        capture("05-mac-catalog", app: app)
        starter.tap()
        XCTAssertTrue(app.buttons["Preview in 3D"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Preview in 3D"].isHittable)
        capture("06-mac-detail", app: app)
        app.buttons["Close"].tap()
    }
    #else
    func testAccessibilityTextUsesSingleColumn() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenOnboarding", "YES", "FFISH_SNAPSHOT_APP_LANGUAGE=en",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let starter = app.buttons["model.35559c2236d04c1a80ccbe08cae863c6"]
        XCTAssertTrue(starter.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(starter.frame.width, app.frame.width * 0.8)
        capture("05-accessibility-text", app: app)
    }
    #endif

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
