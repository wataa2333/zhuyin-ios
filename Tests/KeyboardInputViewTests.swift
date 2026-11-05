import UIKit
import XCTest

@MainActor
final class KeyboardInputViewTests: XCTestCase {
    func testFirstMeasurementDoesNotDependOnKeyPagesOrPriorHostHeight() {
        let view = KeyboardInputView(frame: CGRect(x: 0, y: 0, width: 390, height: 100), inputViewStyle: .keyboard)
        XCTAssertTrue(view.allowsSelfSizing)
        XCTAssertEqual(view.intrinsicContentSize.height, 242 + view.safeAreaInsets.bottom)
        view.frame.size.height = 180
        XCTAssertEqual(view.intrinsicContentSize.height, 242 + view.safeAreaInsets.bottom)
        view.contentHeight = 193
        XCTAssertEqual(view.intrinsicContentSize.height, 193 + view.safeAreaInsets.bottom)
    }

    func testNearbyBlankSpaceActivatesToggleWithoutStealingAnotherControl() {
        let view = KeyboardInputView(frame: CGRect(x: 0, y: 0, width: 390, height: 242), inputViewStyle: .keyboard)
        let toggle = NearbyTouchButton(type: .system)
        toggle.frame = CGRect(x: 326, y: 0, width: 64, height: 44)
        let slot = UIView(frame: toggle.frame)
        toggle.frame = slot.bounds
        slot.addSubview(toggle)
        view.addSubview(slot)
        view.nearbyTouchTarget = toggle
        let nearby = CGPoint(x: 318, y: 50)
        XCTAssertTrue(view.hitTest(nearby, with: nil) === toggle)

        let candidate = UIButton(type: .system)
        candidate.frame = CGRect(x: 300, y: 44, width: 24, height: 30)
        view.addSubview(candidate)
        XCTAssertTrue(view.hitTest(nearby, with: nil) === candidate)
        candidate.isEnabled = false
        XCTAssertTrue(view.hitTest(nearby, with: nil) === candidate)
        toggle.isHidden = true
        XCTAssertFalse(view.hitTest(CGPoint(x: 328, y: 50), with: nil) === toggle)
    }
}
