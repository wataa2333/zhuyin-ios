import UIKit
import XCTest

@MainActor
final class CandidateListTests: XCTestCase {
    private func makeList() -> CandidateListView {
        let list = CandidateListView(frame: CGRect(x: 0, y: 0, width: 350, height: 220))
        list.updateViewport(firstRowWidth: 285)
        list.update(titles: (0..<30).map { "候选\($0)" }, highlightsFirst: true)
        return list
    }

    func testClippedTrailingWordMovesDownAsTheSameButtonWithoutADuplicate() {
        let list = makeList()
        let before = list.subviews.compactMap { $0 as? UIButton }
        let clipped = before.first { $0.frame.minX < 285 && $0.frame.maxX > 285 }
        XCTAssertNotNil(clipped)
        list.prepareTransition(expanded: true)
        list.applyLayout()
        let after = list.subviews.compactMap { $0 as? UIButton }
        XCTAssertEqual(Set(before.map(ObjectIdentifier.init)), Set(after.map(ObjectIdentifier.init)))
        XCTAssertEqual(after.count, 30)
        XCTAssertGreaterThan(clipped?.frame.minY ?? 0, 0)
        XCTAssertEqual(after.filter { $0.currentTitle == clipped?.currentTitle }.count, 1)
    }

    func testScrollingDoesNotRebuildOrRepositionCandidateButtons() {
        let list = makeList()
        list.prepareTransition(expanded: true)
        list.applyLayout()
        let buttons = list.subviews.compactMap { $0 as? UIButton }
        let frames = buttons.map(\.frame)
        for offset in stride(from: 0, through: 150, by: 5) {
            list.contentOffset.y = CGFloat(offset)
            list.layoutIfNeeded()
            XCTAssertEqual(buttons.map(\.frame), frames)
            XCTAssertEqual(list.subviews.compactMap { $0 as? UIButton }.count, 30)
        }
    }

    func testToggleAreaRemainsAvailableAtTheTopAfterScrolling() {
        let list = makeList()
        list.prepareTransition(expanded: true)
        list.applyLayout()
        list.contentOffset.y = 80
        XCTAssertFalse(list.point(inside: CGPoint(x: 310, y: 100), with: nil))
        XCTAssertTrue(list.point(inside: CGPoint(x: 310, y: 150), with: nil))
    }

    func testDraggingAlwaysCancelsCandidateControlTracking() {
        let list = makeList()
        XCTAssertFalse(list.delaysContentTouches)
        XCTAssertTrue(list.canCancelContentTouches)
        XCTAssertTrue(list.touchesShouldCancel(in: UIButton(type: .system)))
        XCTAssertTrue(list.touchesShouldCancel(in: UILabel()))
    }

    func testCandidatePressHasAVisibleCellBackgroundAndCancellationClearsIt() {
        let list = makeList()
        let buttons = list.subviews.compactMap { $0 as? CandidateButton }
        let button = buttons[1]
        button.isHighlighted = true
        XCTAssertTrue(button.backgroundColor?.isEqual(UIColor.systemGray3) == true)
        button.cancelTracking(with: nil)
        XCTAssertFalse(button.isHighlighted)
        XCTAssertTrue(button.backgroundColor?.isEqual(UIColor.clear) == true)
        let first = buttons[0]
        first.isHighlighted = true
        first.cancelTracking(with: nil)
        XCTAssertTrue(first.backgroundColor?.isEqual(UIColor.secondarySystemGroupedBackground) == true)
    }

    func testReleasedCandidateCacheCanBeRebuiltWithoutStaleButtons() {
        let list = makeList()
        list.releaseCachedContent()
        XCTAssertEqual(list.subviews.compactMap { $0 as? UIButton }.count, 0)
        list.update(titles: ["你", "好"], highlightsFirst: false)
        XCTAssertEqual(list.subviews.compactMap { $0 as? UIButton }.count, 2)
        XCTAssertEqual(list.subviews.compactMap { ($0 as? UIButton)?.currentTitle }, ["你", "好"])
    }
}
