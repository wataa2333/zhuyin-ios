import UIKit
import XCTest

final class KeyPreviewTests: XCTestCase {
    func testMiddleRowPreviewJoinsThePressedKeyAtItsOriginalPosition() {
        let key = CGRect(x: 160, y: 100, width: 34, height: 42)
        let geometry = KeyPreviewGeometry(key: key, viewport: CGRect(x: 0, y: 0, width: 390, height: 242), compact: false)
        XCTAssertEqual(geometry.frame.width, 56)
        XCTAssertEqual(geometry.frame.height, 108)
        XCTAssertEqual(geometry.frame.midX, key.midX)
        XCTAssertEqual(geometry.frame.minY + geometry.anchorLeft.y, key.minY + 1)
        XCTAssertEqual(geometry.frame.maxY, key.maxY)
        XCTAssertEqual(geometry.anchorLeft.x + geometry.frame.minX, key.minX)
        XCTAssertEqual(geometry.anchorRight.x + geometry.frame.minX, key.maxX)
    }

    func testFirstRowKeepsFullHeadSizeInsideTheKeyboardBoundary() {
        let key = CGRect(x: 160, y: 46, width: 34, height: 42)
        let geometry = KeyPreviewGeometry(key: key, viewport: CGRect(x: 0, y: 0, width: 390, height: 242), compact: false)
        XCTAssertEqual(geometry.frame.minY, 2)
        XCTAssertEqual(geometry.head.height, 52)
        XCTAssertEqual(geometry.frame.maxY, key.maxY)
    }

    func testLeftAndRightPreviewsStayInsideViewportAndKeepTheirNeckAnchored() {
        for x in [CGFloat(7), CGFloat(349)] {
            let key = CGRect(x: x, y: 100, width: 34, height: 42)
            let geometry = KeyPreviewGeometry(key: key, viewport: CGRect(x: 0, y: 0, width: 390, height: 242), compact: false)
            XCTAssertGreaterThanOrEqual(geometry.frame.minX, 2)
            XCTAssertLessThanOrEqual(geometry.frame.maxX, 388)
            XCTAssertEqual(geometry.frame.minX + geometry.anchorLeft.x, key.minX)
            XCTAssertEqual(geometry.frame.minX + geometry.anchorRight.x, key.maxX)
        }
    }
}
