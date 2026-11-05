import Foundation
import XCTest

final class CompositionTextWriterTests: XCTestCase {
    /// Models hosts that retain their current marked range when asked to mark an empty string.
    private final class Document: CompositionTextDocument {
        var committed = ""
        var marked: String?
        var operations: [String] = []

        func setMarkedText(_ text: String, selectedRange: NSRange) {
            operations.append("mark:\(text)")
            XCTAssertEqual(selectedRange.location, text.utf16.count)
            if !text.isEmpty { marked = text }
        }

        func unmarkText() {
            operations.append("unmark")
            committed += marked ?? ""
            marked = nil
        }

        func insertText(_ text: String) {
            operations.append("insert:\(text)")
            committed += text
        }
    }

    func testSelectedPhraseReplacesReadingBeforeUnmarking() {
        let document = Document()
        var writer = CompositionTextWriter()
        writer.update("ㄓㄨㄥˋ ㄔㄡˊ", in: document)
        writer.commit("众筹", in: document)
        writer.update("", in: document)
        XCTAssertEqual(document.committed, "众筹")
        XCTAssertNil(document.marked)
        XCTAssertEqual(document.operations, ["mark:ㄓㄨㄥˋ ㄔㄡˊ", "mark:众筹", "unmark"])
    }

    func testSelectingIndividualCharactersDoesNotCommitRawFirstSyllable() {
        let document = Document()
        var writer = CompositionTextWriter()
        writer.update("ㄓㄨㄥˋ ㄔㄡˊ", in: document)
        writer.commit("众", in: document)
        writer.update("ㄔㄡˊ", in: document)
        XCTAssertEqual(document.committed, "众")
        XCTAssertEqual(document.marked, "ㄔㄡˊ")
        writer.commit("筹", in: document)
        XCTAssertEqual(document.committed, "众筹")
        XCTAssertNil(document.marked)
        XCTAssertFalse(document.operations.contains("mark:"))
    }

    func testIdleCandidateIsInsertedAndUTF16SelectionHandlesEmoji() {
        let document = Document()
        var writer = CompositionTextWriter()
        writer.commit("你好", in: document)
        writer.update("ㄒㄧㄣ", in: document)
        writer.commit("❤️", in: document)
        XCTAssertEqual(document.committed, "你好❤️")
        XCTAssertEqual(writer.markedText, "")
    }
}
