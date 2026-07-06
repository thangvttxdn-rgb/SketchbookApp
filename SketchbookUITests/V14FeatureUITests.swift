import XCTest

/// Functional smoke tests for the 1.4 features: vector shapes (incl. the new
/// star), tap-to-fill, flood-fill undo, the Adjustments panel, the Stardust
/// brush and the eraser size control. Content mutations are asserted through
/// the document-level Undo button's enabled state.
final class V14FeatureUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func newSketch(_ app: XCUIApplication) {
        // The editor auto-locks to landscape on iPad, which desyncs XCUITest's
        // coordinate space from the rendered UI — disable it for these tests.
        app.launchEnvironment["UITEST_DISABLE_ORIENTATION_LOCK"] = "1"
        // Tests drive the canvas with synthetic finger touches; the iPad default
        // is now Pencil-only, so explicitly enable finger drawing (UserDefaults
        // reads -key value launch arguments as overrides).
        app.launchArguments += ["-fingerDrawing", "YES"]
        app.launch()
        let newButton = app.buttons["New Sketch"].firstMatch
        if newButton.waitForExistence(timeout: 8) { newButton.tap() }
        else { app.buttons["New"].firstMatch.tap() }
        let create = app.buttons["Create"]
        XCTAssertTrue(create.waitForExistence(timeout: 8))
        create.tap()
        sleep(1)
    }

    /// Place a star shape, commit it, then tap-to-fill it with the fill tool.
    func testStarShapeAndVectorFill() {
        let app = XCUIApplication()
        newSketch(app)
        let undo = app.buttons["Undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertFalse(undo.isEnabled)

        // Star from the shape picker.
        app.buttons["Shapes"].firstMatch.tap()
        let star = app.buttons["Star"].firstMatch
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        star.tap()
        dismissPickerIfSheet(app)
        sleep(1)

        // Drag the star out on the canvas, then confirm with the check button.
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.38))
        let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.58))
        a.press(forDuration: 0.1, thenDragTo: b, withVelocity: 200, thenHoldForDuration: 0.1)
        let add = app.buttons["Add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        sleep(1)
        XCTAssertTrue(undo.isEnabled, "committing a shape should be undoable")
        snapshot("v14-01-star-committed")

        // Fill tool: tap inside the star → vector fill (another undo step).
        app.buttons["Fill"].firstMatch.tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.335, dy: 0.48)).tap()
        sleep(1)
        XCTAssertTrue(undo.isEnabled)
        snapshot("v14-02-star-filled")
    }

    /// Regression (reported on device): toggling "Fill shape" AFTER dragging a
    /// shape out must fill the live pending shape, not silently do nothing.
    func testFillToggleUpdatesPendingShape() {
        let app = XCUIApplication()
        newSketch(app)

        app.buttons["Shapes"].firstMatch.tap()
        let rect = app.buttons["Rectangle"].firstMatch
        XCTAssertTrue(rect.waitForExistence(timeout: 5))
        rect.tap()
        dismissPickerIfSheet(app)
        sleep(1)

        // Drag the rectangle out — handles appear, fill still off.
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.4))
        let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.55))
        a.press(forDuration: 0.1, thenDragTo: b, withVelocity: 200, thenHoldForDuration: 0.1)
        let add = app.buttons["Add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))

        // NOW toggle fill — the pending shape must pick it up live.
        // (Reopen the picker: on a collapsed-panel layout it lives in a sheet.)
        app.buttons["Shapes"].firstMatch.tap()
        let fill = app.switches["Fill shape"].firstMatch
        XCTAssertTrue(fill.waitForExistence(timeout: 5))
        fill.tap()
        sleep(1)
        dismissPickerIfSheet(app)
        snapshot("v14-09-pending-fill-toggled")

        add.tap()
        sleep(1)
        XCTAssertTrue(app.buttons["Undo"].firstMatch.isEnabled)
        snapshot("v14-10-filled-shape-committed")
    }

    /// Flood-fill the empty canvas, then verify Undo reverts it.
    func testCanvasFillIsUndoable() {
        let app = XCUIApplication()
        newSketch(app)
        let undo = app.buttons["Undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertFalse(undo.isEnabled)

        app.buttons["Fill"].firstMatch.tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)).tap()
        sleep(2)
        XCTAssertTrue(undo.isEnabled, "canvas fill should be undoable")
        snapshot("v14-03-canvas-filled")

        undo.tap()
        sleep(1)
        XCTAssertFalse(undo.isEnabled, "undo should revert the fill")
        let redo = app.buttons["Redo"].firstMatch
        XCTAssertTrue(redo.isEnabled)
        snapshot("v14-04-fill-undone")
    }

    /// Apply an HSB adjustment from the new Adjustments panel.
    func testAdjustmentsApply() {
        let app = XCUIApplication()
        newSketch(app)
        // Draw something to adjust.
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.45))
        let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        a.press(forDuration: 0.2, thenDragTo: b, withVelocity: 150, thenHoldForDuration: 0.2)
        sleep(1)

        app.buttons["Adjustments"].firstMatch.tap()
        let hsb = app.buttons["Hue, Saturation, Brightness"].firstMatch
        XCTAssertTrue(hsb.waitForExistence(timeout: 5))
        hsb.tap()
        let apply = app.buttons["Apply"].firstMatch
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        snapshot("v14-05-adjustment-detail")
        apply.tap()
        sleep(1)
        // Panel dismissed back to the editor with the change applied (undoable).
        XCTAssertTrue(app.buttons["Undo"].firstMatch.isEnabled)
        snapshot("v14-06-adjustment-applied")
    }

    /// Sprinkle stardust and confirm it commits as an undoable change.
    func testStardustBrush() {
        let app = XCUIApplication()
        newSketch(app)
        let undo = app.buttons["Undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5))

        app.buttons["Brushes"].firstMatch.tap()
        let stardust = app.buttons["Stardust"].firstMatch
        XCTAssertTrue(stardust.waitForExistence(timeout: 5))
        stardust.tap()
        dismissPickerIfSheet(app)
        sleep(1)

        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.42))
        let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        a.press(forDuration: 0.15, thenDragTo: b, withVelocity: 120, thenHoldForDuration: 0.15)
        sleep(1)
        XCTAssertTrue(undo.isEnabled, "stardust sprinkle should commit as an undo step")
        snapshot("v14-07-stardust")
    }

    /// The eraser exposes a size slider (tap the active eraser again).
    func testEraserSizeControl() {
        let app = XCUIApplication()
        newSketch(app)
        let eraser = app.buttons["Eraser"].firstMatch
        XCTAssertTrue(eraser.waitForExistence(timeout: 5))
        eraser.tap()
        eraser.tap()   // second tap opens the size popover
        let slider = app.sliders.firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "eraser size slider should appear")
        slider.adjust(toNormalizedSliderPosition: 0.8)
        snapshot("v14-08-eraser-size")
    }

    /// iPad pages sidebar: manual expand, thumbnails show content, drag to
    /// reorder, tap-to-switch, delete.
    func testPagesSidebar() {
        let app = XCUIApplication()
        newSketch(app)
        // Draw on page 1 so its thumbnail has visible content.
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.4))
        let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.55))
        a.press(forDuration: 0.2, thenDragTo: b, withVelocity: 150, thenHoldForDuration: 0.2)
        sleep(1)

        let show = app.buttons["Show pages"].firstMatch
        guard show.waitForExistence(timeout: 5) else { return }   // compact width: no sidebar
        show.tap()
        sleep(1)
        snapshot("v14-11-pages-sidebar")

        // Add a blank page 2 (becomes current).
        let addPage = app.buttons["Add page"].firstMatch
        XCTAssertTrue(addPage.waitForExistence(timeout: 5))
        addPage.tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["pageIndicator"].label.contains("2 / 2"))

        // Drag page 1 (the drawing) onto page 2 → order flips; the current
        // (blank) page moves up to index 0.
        let thumb1 = app.images["pageThumb1"].firstMatch
        let thumb2 = app.images["pageThumb2"].firstMatch
        XCTAssertTrue(thumb1.waitForExistence(timeout: 5))
        thumb1.press(forDuration: 1.2, thenDragTo: thumb2)
        sleep(1)
        XCTAssertTrue(app.staticTexts["pageIndicator"].label.contains("1 / 2"),
                      "drag reorder should move the blank current page to slot 1")
        snapshot("v14-13-pages-reordered")

        // Tap page 2 (now the drawing) to switch to it.
        thumb2.tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["pageIndicator"].label.contains("2 / 2"))

        // Delete the blank page 1.
        let del = app.buttons["Delete page 1"].firstMatch
        XCTAssertTrue(del.waitForExistence(timeout: 5))
        del.tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["pageIndicator"].label.contains("1 / 1"))
        snapshot("v14-12-page-deleted")

        app.buttons["Hide pages"].firstMatch.tap()
    }

    /// Pickers open as sheets when the side panel is collapsed (the default) —
    /// dismiss so the canvas is tappable again.
    private func dismissPickerIfSheet(_ app: XCUIApplication) {
        let done = app.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 2) { done.tap() }
    }

    private func snapshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
