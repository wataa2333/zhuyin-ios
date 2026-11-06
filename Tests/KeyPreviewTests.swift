import UIKit
import XCTest

@MainActor
final class KeyPreviewTests: XCTestCase {
    func testMiddleRowPreviewCoversThePressedKeyAtItsOriginalPosition() {
        let key = CGRect(x: 160, y: 100, width: 34, height: 42)
        let geometry = KeyPreviewGeometry(key: key, viewport: CGRect(x: 0, y: 0, width: 390, height: 242), compact: false)
        XCTAssertEqual(geometry.frame.width, 56)
        XCTAssertEqual(geometry.frame.height, 108)
        XCTAssertEqual(geometry.frame.midX, key.midX)
        XCTAssertEqual(geometry.frame.maxY, key.maxY)
        XCTAssertEqual(geometry.keyBody.offsetBy(dx: geometry.frame.minX, dy: geometry.frame.minY), key)
    }

    func testFirstRowKeepsFullHeadSizeInsideTheKeyboardBoundary() {
        let key = CGRect(x: 160, y: 46, width: 34, height: 42)
        let geometry = KeyPreviewGeometry(key: key, viewport: CGRect(x: 0, y: 0, width: 390, height: 242), compact: false)
        XCTAssertEqual(geometry.frame.minY, 2)
        XCTAssertEqual(geometry.head.height, 52)
        XCTAssertEqual(geometry.frame.maxY, key.maxY)
    }

    func testLeftAndRightPreviewsStayInsideViewportAndCoverTheirSourceKey() {
        for x in [CGFloat(7), CGFloat(349)] {
            let key = CGRect(x: x, y: 100, width: 34, height: 42)
            let geometry = KeyPreviewGeometry(key: key, viewport: CGRect(x: 0, y: 0, width: 390, height: 242), compact: false)
            XCTAssertGreaterThanOrEqual(geometry.frame.minX, 2)
            XCTAssertLessThanOrEqual(geometry.frame.maxX, 388)
            XCTAssertEqual(geometry.keyBody.offsetBy(dx: geometry.frame.minX, dy: geometry.frame.minY), key)
        }
    }

    func testPreviewHasOneFilledContourWithoutTransparentSeams() {
        // Include the clamped top row and both edge keys, where shapes overlap differently.
        for compact in [false, true] {
            for y in [CGFloat(47), CGFloat(100)] {
                for x in [CGFloat(7), CGFloat(160), CGFloat(349)] {
                    let key = CGRect(x: x, y: y, width: 34, height: compact ? 32 : 42)
                    let geometry = KeyPreviewGeometry(key: key,
                        viewport: CGRect(x: 0, y: 0, width: 390, height: 242), compact: compact)
                    let outline = geometry.outline
                    var moves = 0
                    var closes = 0
                    outline.cgPath.applyWithBlock { element in
                        if element.pointee.type == .moveToPoint { moves += 1 }
                        if element.pointee.type == .closeSubpath { closes += 1 }
                    }
                    XCTAssertEqual(moves, 1)
                    XCTAssertEqual(closes, 1)
                    for scanY in stride(from: CGFloat(1), to: geometry.keyBody.maxY - 1, by: 0.5) {
                        XCTAssertTrue(outline.contains(CGPoint(x: geometry.keyBody.midX, y: scanY)),
                                      "Transparent seam at \(scanY), key \(key)")
                    }
                    // A cross-section through the former overlapping paths must remain one solid span.
                    for scanY in [geometry.head.maxY - 3, geometry.keyBody.minY + 0.5] {
                        let hits = stride(from: CGFloat(0.5), to: geometry.frame.width, by: 0.5)
                            .map { outline.contains(CGPoint(x: $0, y: scanY)) }
                        guard let first = hits.firstIndex(of: true), let last = hits.lastIndex(of: true) else {
                            XCTFail("Empty cross-section at \(scanY), key \(key)")
                            continue
                        }
                        XCTAssertTrue(hits[first...last].allSatisfy { $0 })
                    }
                    // Bottom corners are rounded, while the center still covers the original key.
                    XCTAssertFalse(outline.contains(CGPoint(x: geometry.keyBody.minX + 0.1,
                                                           y: geometry.keyBody.maxY - 0.1)))
                    XCTAssertFalse(outline.contains(CGPoint(x: geometry.keyBody.maxX - 0.1,
                                                           y: geometry.keyBody.maxY - 0.1)))
                    XCTAssertTrue(outline.contains(CGPoint(x: geometry.keyBody.midX,
                                                          y: geometry.keyBody.maxY - 0.5)))
                }
            }
        }
    }
}
