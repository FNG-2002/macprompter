import XCTest
import AppKit
import SwiftUI
@testable import MacPrompter

@MainActor
final class OverlayAppearanceTests: XCTestCase {
    func testOpacityDefaultsToOpaqueAndIsClamped() throws {
        let legacy = #"{"mode":"automatic","font":"system","fontSize":28,"lineSpacing":12,"speed":36,"width":620,"height":300,"countdownSeconds":3,"mirror":false,"focusLine":true,"docked":true,"displayID":0,"reduceMotion":false}"#
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data(legacy.utf8)).prompterOpacity, 1)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var prefs = Preferences()
        prefs.prompterOpacity = 0.05
        defaults.set(try JSONEncoder().encode(prefs), forKey: "preferences.v1")
        XCTAssertEqual(PreferenceStore(defaults: defaults).value.prompterOpacity, 0.2)
        prefs.prompterOpacity = 0.6
        defaults.set(try JSONEncoder().encode(prefs), forKey: "preferences.v1")
        XCTAssertEqual(PreferenceStore(defaults: defaults).value.prompterOpacity, 0.6)
    }

    func testOverlayBackgroundUsesOpacity() throws {
        let model = AppModel.shared
        let original = model.preferences.value
        defer { model.preferences.value = original }
        model.preferences.value.prompterOpacity = 0.4
        let view = NSHostingView(rootView: OverlayView(model: model, topInset: 32))
        view.frame = NSRect(x: 0, y: 0, width: 620, height: 332)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        // A point inside the shape, below the text area and the footer's text.
        let alpha = try XCTUnwrap(bitmap.colorAt(x: 310, y: 40)).alphaComponent
        XCTAssertEqual(alpha, 0.4, accuracy: 0.05)
    }

    func testDockedPrompterGrowsSymmetricallyAndDownward() {
        var start = Preferences()
        start.width = 620; start.height = 300
        var prefs = start
        prefs.resize(from: start, edge: .right, dx: 50, dy: 0)
        XCTAssertEqual(prefs.width, 720)
        XCTAssertEqual(prefs.height, 300)
        prefs.resize(from: start, edge: .bottomLeft, dx: -20, dy: -80)
        XCTAssertEqual(prefs.width, 660)
        XCTAssertEqual(prefs.height, 380)
        XCTAssertNil(prefs.floatingX)
        prefs.resize(from: start, edge: .bottom, dx: 0, dy: 5000)
        XCTAssertEqual(prefs.height, Preferences.heightRange.lowerBound)
        prefs.resize(from: start, edge: .right, dx: 5000, dy: 0)
        XCTAssertEqual(prefs.width, Preferences.widthRange.upperBound)
    }

    func testFloatingPrompterKeepsOppositeEdges() {
        var start = Preferences()
        start.docked = false; start.width = 600; start.height = 300
        start.floatingX = 100; start.floatingY = 500
        var prefs = start
        prefs.resize(from: start, edge: .left, dx: -40, dy: 0)
        XCTAssertEqual(prefs.width, 640)
        XCTAssertEqual(prefs.floatingX, 60)      // right edge stays at 700
        prefs.resize(from: start, edge: .bottomRight, dx: 30, dy: -100)
        XCTAssertEqual(prefs.width, 630)
        XCTAssertEqual(prefs.height, 400)
        XCTAssertEqual(prefs.floatingX, 100)
        XCTAssertEqual(prefs.floatingY, 400)     // top edge stays at 800
    }

    func testLargerSizesSurviveRestart() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var prefs = Preferences()
        prefs.width = 1400; prefs.height = 800
        defaults.set(try JSONEncoder().encode(prefs), forKey: "preferences.v1")
        let restored = PreferenceStore(defaults: defaults).value
        XCTAssertEqual(restored.width, 1400)
        XCTAssertEqual(restored.height, 800)
    }

    /// Regression: the handles must receive the drag (not move the panel).
    func testDraggingEdgesResizesTheRealPanel() throws {
        let model = AppModel.shared
        let original = model.preferences.value
        defer { model.preferences.value = original; model.session.setHover(false) }
        for docked in [true, false] {
            model.preferences.value.docked = docked
            model.preferences.value.width = 620; model.preferences.value.height = 300
            let panel = PrompterPanel(contentRect: NSRect(x: 200, y: 200, width: 620, height: 332), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isMovableByWindowBackground = !docked
            let host = NSHostingView(rootView: OverlayView(model: model, topInset: 32))
            panel.contentView = host
            panel.orderFrontRegardless()
            defer { panel.orderOut(nil) }
            host.layoutSubtreeIfNeeded()
            let handle = try XCTUnwrap(host.hitTest(NSPoint(x: 310, y: 4)) as? PanelResizeHandle.HandleView)
            XCTAssertFalse(handle.mouseDownCanMoveWindow)
            XCTAssertEqual(handle.edge, .bottom)
            // Synthetic events do not move the real pointer; derive it from the event.
            let fromEvent: (NSEvent) -> NSPoint = { $0.window!.convertPoint(toScreen: $0.locationInWindow) }
            handle.locate = fromEvent

            func send(_ type: NSEvent.EventType, _ point: NSPoint) {
                panel.sendEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
            }
            // Bottom edge 80 pt down (window coordinates, y up).
            model.session.gate.isHovering = false
            send(.leftMouseDown, NSPoint(x: 310, y: 4))
            XCTAssertTrue(model.isResizingPrompter)
            XCTAssertTrue(model.session.gate.isHovering, "hover pause holds while resizing")
            send(.leftMouseDragged, NSPoint(x: 310, y: -76))
            XCTAssertTrue(model.session.gate.isHovering, "leaving the panel during the drag keeps the pause")
            send(.leftMouseUp, NSPoint(x: 310, y: -76))
            XCTAssertFalse(model.isResizingPrompter)
            XCTAssertEqual(model.preferences.value.height, 380, "docked=\(docked)")
            XCTAssertEqual(panel.frame.origin, NSPoint(x: 200, y: 200), "the panel itself must not be dragged")

            let right = try XCTUnwrap(host.hitTest(NSPoint(x: 620 - (docked ? 16 : 4), y: 160)) as? PanelResizeHandle.HandleView)
            XCTAssertEqual(right.edge, .right)
            right.locate = fromEvent
            send(.leftMouseDown, NSPoint(x: 620 - (docked ? 16 : 4), y: 160))
            send(.leftMouseDragged, NSPoint(x: 620 - (docked ? 16 : 4) + 40, y: 160))
            send(.leftMouseUp, NSPoint(x: 620 - (docked ? 16 : 4) + 40, y: 160))
            XCTAssertEqual(model.preferences.value.width, docked ? 700 : 660, "docked grows on both sides")
        }
    }
}
