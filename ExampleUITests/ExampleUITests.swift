import XCTest

final class ExampleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["item-count"].waitForExistence(timeout: 15))
    }

    override func tearDownWithError() throws {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    private func waitForCount(_ count: Int) {
        let expected = NSPredicate(format: "label == %@", "\(count) cells")
        expectation(for: expected, evaluatedWith: app.staticTexts["item-count"])
        waitForExpectations(timeout: 10)
    }

    private func waitForEnabled(_ button: XCUIElement) {
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: button)
        waitForExpectations(timeout: 10)
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAddSelectAndDelete() {
        waitForCount(256)
        app.buttons["add"].tap()
        waitForEnabled(app.buttons["add"])
        app.buttons["add"].tap()
        waitForEnabled(app.buttons["add"])
        waitForCount(258)
        XCTAssertTrue(app.buttons["cell-256"].exists)
        XCTAssertTrue(app.buttons["cell-257"].exists)

        app.buttons["Edit"].tap()
        XCTAssertFalse(app.buttons["delete"].isEnabled)
        app.buttons["cell-256"].tap()
        app.buttons["cell-257"].tap()
        XCTAssertTrue(app.buttons["cell-256"].isSelected)
        XCTAssertTrue(app.buttons["cell-257"].isSelected)
        attachScreenshot("selection")
        app.buttons["delete"].tap()
        waitForCount(256)
        waitForEnabled(app.buttons["Done"])
        XCTAssertFalse(app.buttons["cell-256"].exists)
        XCTAssertFalse(app.buttons["cell-257"].exists)
        XCTAssertTrue(app.buttons["cell-0"].exists)
        XCTAssertFalse(app.buttons["delete"].isEnabled)
        app.buttons["Done"].tap()
    }

    func testRotationAndFullWindowLayout() {
        let window = app.windows.firstMatch
        let grid = app.scrollViews["grid"]
        XCTAssertGreaterThan(grid.frame.height, window.frame.height * 0.7)
        XCTAssertEqual(grid.frame.width, window.frame.width, accuracy: 2)
        attachScreenshot("portrait")
        app.buttons["Edit"].tap()
        app.buttons["cell-0"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["cell-0"].isSelected)
        XCTAssertTrue(app.buttons["delete"].isEnabled)
        XCTAssertGreaterThan(grid.frame.width, grid.frame.height)
        attachScreenshot("landscape")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["cell-0"].isSelected)
        app.buttons["Done"].tap()
        grid.swipeUp()
        grid.swipeDown()
        waitForCount(256)
    }

    func testDragReordersCells() {
        app.buttons["Edit"].tap()
        let source = app.buttons["cell-0"]
        let destination = app.buttons["cell-2"]
        let targetFrame = destination.frame
        source.press(forDuration: 0.6, thenDragTo: destination)
        let moved = NSPredicate { _, _ in
            abs(source.frame.minX - targetFrame.minX) < 2 && abs(source.frame.minY - targetFrame.minY) < 2
        }
        expectation(for: moved, evaluatedWith: source)
        waitForExpectations(timeout: 10)
        waitForCount(256)
        attachScreenshot("reordered")
    }
}
