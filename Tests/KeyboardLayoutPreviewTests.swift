import UIKit
import XCTest

@MainActor
final class KeyboardLayoutPreviewTests: XCTestCase {
    private final class SettingsProxy: NSObject, UITextDocumentProxy {
        var documentContextBeforeInput: String? { "" }
        var documentContextAfterInput: String? { "" }
        var documentInputMode: UITextInputMode? { nil }
        let documentIdentifier = UUID()
        var textContentType: UITextContentType! = .nickname
        var selectedText: String?
        var hasText: Bool { true }
        var reply: String?
        init(code: String) { selectedText = code }
        func insertText(_ text: String) { reply = text; selectedText = nil }
        func deleteBackward() {}
        func adjustTextPosition(byCharacterOffset offset: Int) {}
        func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
        func unmarkText() {}
    }

    private func child(_ identifier: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        return view.subviews.lazy.compactMap { child(identifier, in: $0) }.first
    }

    func testLivePreviewUsesProductionCandidateAndKeyFramesForEveryProfile() throws {
        let controller = KeyboardViewController.makeLayoutPreview(.defaults, showsPinyin: true)
        var custom = KeyboardLayoutConfiguration.defaults
        custom.candidateBarHeight = 60
        custom.topInset = 0
        custom.keyHeight = 48
        custom.rowSpacing = 12
        custom.toolbarSpacing = 5
        custom.bottomInset = 8
        for layout in [KeyboardLayoutConfiguration.defaults, custom, .defaults] {
            for expanded in [false, true, false] {
                controller.updateLayoutPreview(layout, showsPinyin: true, expanded: expanded)
                controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: layout.contentHeight)
                controller.view.layoutIfNeeded()
                let list = try XCTUnwrap(child("keyboard.candidates", in: controller.view) as? CandidateListView)
                let keys = try XCTUnwrap(child("keyboard.keyArea", in: controller.view))
                let listFrame = list.convert(list.bounds, to: controller.view)
                let keyFrame = keys.convert(keys.bounds, to: controller.view)
                XCTAssertEqual(controller.layoutConfiguration, layout)
                XCTAssertEqual(listFrame.minY, layout.topInset)
                XCTAssertEqual(listFrame.height, expanded ? layout.candidatePanelHeight : layout.candidateBarHeight)
                XCTAssertEqual(list.candidateBarHeight, layout.candidateBarHeight)
                XCTAssertEqual(keyFrame.minY, layout.topInset + layout.candidateBarHeight + layout.toolbarSpacing)
                XCTAssertEqual(keyFrame.height, layout.keyAreaHeight)
                XCTAssertEqual(keyFrame.maxY, layout.contentHeight - layout.bottomInset)
            }
        }
    }

    func testSyncFieldAcceptsOnlyAMatchingReceiptAndReportsItOnce() {
        let code = KeyboardPreferences.syncCode(pinyin: true, feedback: KeyFeedbackSettings(), layout: .defaults)
        let coordinator = KeyboardSyncField.Coordinator()
        coordinator.success = KeyboardPreferences.syncReply(for: code)
        coordinator.failure = KeyboardPreferences.syncReply(for: code, succeeded: false)
        let field = UITextField()
        field.text = code
        let whole = NSRange(location: 0, length: (code as NSString).length)
        XCTAssertFalse(coordinator.textField(field, shouldChangeCharactersIn: whole, replacementString: "你好"))
        XCTAssertTrue(coordinator.textField(field, shouldChangeCharactersIn: whole, replacementString: coordinator.success))
        let received = expectation(description: "One real keyboard receipt")
        received.assertForOverFulfill = true
        coordinator.onReply = { success in XCTAssertTrue(success); received.fulfill() }
        field.text = coordinator.success
        coordinator.changed(field)
        coordinator.changed(field)
        wait(for: [received], timeout: 1)
    }

    func testRealSettingsReceiverOverwritesPersistedAndVisibleDimensionsBeforeReplying() {
        let oldLayout = KeyboardPreferences.localLayout
        let oldPinyin = KeyboardPreferences.localPinyin
        let oldFeedback = KeyboardPreferences.localFeedback
        addTeardownBlock {
            try? KeyboardPreferences.saveLocally(oldLayout)
            KeyboardPreferences.saveLocally(oldPinyin)
            KeyboardPreferences.saveLocally(oldFeedback)
        }
        let controller = KeyboardViewController.makeLayoutPreview(.defaults, showsPinyin: false)
        controller.updateLayoutPreview(.defaults, showsPinyin: false, expanded: false)
        var layout = KeyboardLayoutConfiguration.defaults
        layout.candidateBarHeight = 40
        layout.topInset = 0
        layout.toolbarSpacing = 5
        let code = KeyboardPreferences.syncCode(pinyin: true, feedback: oldFeedback, layout: layout)
        let proxy = SettingsProxy(code: code)
        XCTAssertTrue(controller.synchronizeSettings(using: proxy))
        XCTAssertEqual(KeyboardPreferences.localLayout, layout)
        XCTAssertEqual(controller.layoutConfiguration, layout)
        XCTAssertEqual(proxy.reply, KeyboardPreferences.syncReply(for: code))
        XCTAssertFalse(controller.synchronizeSettings(using: proxy))
    }
}
