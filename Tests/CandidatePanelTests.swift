import UIKit
import XCTest

@MainActor
final class CandidatePanelTests: XCTestCase {
    @MainActor
    private final class Fixture {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        let keyboard = UIView(frame: CGRect(x: 0, y: 44, width: 390, height: 220))
        let candidates = UIView(frame: CGRect(x: 0, y: 44, width: 390, height: 220))
        let toolbar = UIScrollView(frame: CGRect(x: 0, y: 0, width: 330, height: 44))
        let toggle = UIButton(type: .system)
        let panel: CandidatePanelController

        init(keepsCandidatesVisible: Bool = false) {
            toggle.frame = CGRect(x: 338, y: 0, width: 52, height: 44)
            toggle.setImage(UIImage(systemName: "chevron.down"), for: .normal)
            let root = UIViewController()
            window.rootViewController = root
            for view in [keyboard, candidates, toolbar, toggle] { root.view.addSubview(view) }
            for index in 0..<10 {
                let word = UIButton(type: .system)
                word.setTitle("候选\(index)", for: .normal)
                word.frame = CGRect(x: CGFloat(index) * 60, y: 0, width: 59, height: 40)
                toolbar.addSubview(word)
            }
            toolbar.contentSize = CGSize(width: 600, height: 44)
            toolbar.contentOffset.x = 23 // Both edges contain a partially visible word.
            panel = CandidatePanelController(keyboard: keyboard, candidates: candidates, toggle: toggle,
                                             keepsCandidatesVisible: keepsCandidatesVisible)
            panel.onToggleRequested = { [weak panel] in
                guard let panel else { return }
                panel.setExpanded(!panel.isExpanded)
            }
            window.makeKeyAndVisible()
            root.view.layoutIfNeeded()
        }

        func tap() { toggle.sendActions(for: .primaryActionTriggered) }

        func close() {
            panel.setExpanded(false, animated: false)
            window.isHidden = true
        }
    }

    private func finishAnimations() {
        let finished = expectation(description: "Transition settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { finished.fulfill() }
        wait(for: [finished], timeout: 2)
    }

    func testSingleTapExpandsAndSecondTapCollapses() {
        let f = Fixture()
        defer { f.close() }
        f.tap()
        XCTAssertTrue(f.panel.isExpanded)
        finishAnimations()
        XCTAssertTrue(f.keyboard.isHidden)
        XCTAssertFalse(f.candidates.isHidden)
        f.tap()
        XCTAssertFalse(f.panel.isExpanded)
        finishAnimations()
        XCTAssertFalse(f.keyboard.isHidden)
        XCTAssertTrue(f.candidates.isHidden)
        XCTAssertEqual(f.toggle.accessibilityLabel, "展开候选字词")
    }

    func testSharedCandidateListStaysVisibleAndTouchableInBothModes() {
        let f = Fixture(keepsCandidatesVisible: true)
        defer { f.close() }
        XCTAssertFalse(f.candidates.isHidden)
        XCTAssertTrue(f.candidates.isUserInteractionEnabled)
        f.tap()
        f.tap()
        finishAnimations()
        XCTAssertFalse(f.candidates.isHidden)
        XCTAssertEqual(f.candidates.alpha, 1)
        XCTAssertTrue(f.candidates.isUserInteractionEnabled)
        XCTAssertFalse(f.candidates.accessibilityElementsHidden)
    }

    func testTransitionActuallyAnimates() throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion requests an immediate transition")
        let f = Fixture()
        defer { f.close() }
        f.tap()
        XCTAssertFalse(f.keyboard.isHidden)
        XCTAssertFalse(f.candidates.isHidden)
        XCTAssertFalse(f.candidates.layer.animationKeys()?.isEmpty ?? true)
        finishAnimations()
        XCTAssertTrue(f.keyboard.isHidden)
    }

    func testEveryRapidTapChangesTheTargetAndFinalStateStaysCollapsed() {
        let f = Fixture()
        defer { f.close() }
        for index in 1...100 {
            f.tap()
            XCTAssertEqual(f.panel.isExpanded, index % 2 == 1)
            XCTAssertTrue(f.toggle.isUserInteractionEnabled)
        }
        finishAnimations()
        XCTAssertFalse(f.panel.isExpanded)
        XCTAssertTrue(f.candidates.isHidden)
        XCTAssertFalse(f.keyboard.isHidden)
    }

    func testReversalAfterAnimationHasStartedCannotBeOverwrittenByOldCompletion() {
        let f = Fixture()
        defer { f.close() }
        f.tap()
        let reversed = expectation(description: "Reverse halfway")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            f.tap()
            XCTAssertFalse(f.panel.isExpanded)
            reversed.fulfill()
        }
        wait(for: [reversed], timeout: 2)
        finishAnimations()
        XCTAssertFalse(f.panel.isExpanded)
        XCTAssertFalse(f.keyboard.isHidden)
        XCTAssertTrue(f.candidates.isHidden)
    }

    func testIncomingSurfaceAcceptsTouchesDuringBothTransitions() {
        let f = Fixture()
        defer { f.close() }
        let point = CGPoint(x: 100, y: 100)
        f.tap()
        XCTAssertNotNil(f.candidates.hitTest(point, with: nil))
        XCTAssertNil(f.keyboard.hitTest(point, with: nil))
        f.tap()
        XCTAssertNotNil(f.keyboard.hitTest(point, with: nil))
        XCTAssertNil(f.candidates.hitTest(point, with: nil))
    }

    func testToolbarAndClippedLastWordRemainIdenticalAcrossTransitions() {
        let f = Fixture()
        defer { f.close() }
        let frames = f.toolbar.subviews.map(\.frame)
        let hidden = f.toolbar.subviews.map(\.isHidden)
        let bounds = f.toolbar.bounds
        let size = f.toolbar.contentSize
        for _ in 0..<10 {
            f.tap()
            XCTAssertEqual(f.toolbar.bounds, bounds)
            XCTAssertEqual(f.toolbar.contentSize, size)
            XCTAssertEqual(f.toolbar.subviews.map(\.frame), frames)
            XCTAssertEqual(f.toolbar.subviews.map(\.isHidden), hidden)
        }
    }

    func testSelectionCanCollapseWhileOpening() {
        let f = Fixture()
        defer { f.close() }
        f.tap()
        f.panel.setExpanded(false)
        finishAnimations()
        XCTAssertFalse(f.panel.isExpanded)
        XCTAssertTrue(f.candidates.isHidden)
        XCTAssertTrue(f.keyboard.isUserInteractionEnabled)
    }

    func testLifecycleResetCancelsPendingCompletion() {
        let f = Fixture()
        defer { f.close() }
        f.tap()
        f.panel.setExpanded(false, animated: false)
        XCTAssertTrue(f.candidates.isHidden)
        finishAnimations()
        XCTAssertFalse(f.panel.isExpanded)
        XCTAssertTrue(f.candidates.isHidden)
        XCTAssertFalse(f.keyboard.isHidden)
    }

    func testRepeatedExpandedRequestDoesNotHideOrDisableCandidates() {
        let f = Fixture()
        defer { f.close() }
        f.tap()
        f.panel.setExpanded(true)
        finishAnimations()
        XCTAssertTrue(f.panel.isExpanded)
        XCTAssertFalse(f.candidates.isHidden)
        XCTAssertTrue(f.candidates.isUserInteractionEnabled)
        XCTAssertTrue(f.keyboard.accessibilityElementsHidden)
        XCTAssertFalse(f.candidates.accessibilityElementsHidden)
    }
}
