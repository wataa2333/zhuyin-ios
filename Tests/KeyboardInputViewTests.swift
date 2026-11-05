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
}
