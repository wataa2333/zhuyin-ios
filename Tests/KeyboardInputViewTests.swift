import UIKit
import XCTest

@MainActor
final class KeyboardInputViewTests: XCTestCase {
    func testFirstMeasurementDoesNotDependOnKeyPagesOrPriorHostHeight() {
        let view = KeyboardInputView(frame: CGRect(x: 0, y: 0, width: 390, height: 100), inputViewStyle: .keyboard)
        XCTAssertTrue(view.allowsSelfSizing)
        XCTAssertEqual(view.intrinsicContentSize.height, 258)
        view.frame.size.height = 180
        XCTAssertEqual(view.intrinsicContentSize.height, 258)
        view.contentHeight = 193
        XCTAssertEqual(view.intrinsicContentSize.height, 193)
        let container = UIViewController()
        container.view = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 193))
        view.frame = container.view.bounds
        container.view.addSubview(view)
        container.additionalSafeAreaInsets = UIEdgeInsets(top: 30, left: 0, bottom: 40, right: 0)
        container.view.layoutIfNeeded()
        XCTAssertEqual(view.intrinsicContentSize.height, 193)
    }

    func testContentRemainsFixedAcrossTransientHostHeights() {
        let view = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
        var custom = KeyboardLayoutConfiguration.defaults
        custom.keyHeight = 36
        custom.candidateBarHeight = 60
        for configuration in [KeyboardLayoutConfiguration.defaults, custom, .defaults] {
            view.contentHeight = configuration.contentHeight
            for hostHeight in [CGFloat(0), 180, 242, 260, 600] {
                view.frame = CGRect(x: 0, y: 0, width: 390, height: hostHeight)
                view.setNeedsLayout()
                view.layoutIfNeeded()
                XCTAssertEqual(view.contentLayoutGuide.layoutFrame.minY, 0)
                XCTAssertEqual(view.contentLayoutGuide.layoutFrame.height, configuration.contentHeight)
                let fitting = view.systemLayoutSizeFitting(CGSize(width: 390, height: 0),
                    withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
                XCTAssertEqual(fitting.height, configuration.contentHeight)
            }
        }
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
