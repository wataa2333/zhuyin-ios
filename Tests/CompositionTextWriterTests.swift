import Foundation
import XCTest

final class CompositionTextWriterTests: XCTestCase {
    /// Models hosts that retain their current marked range when asked to mark an empty string.
    private final class Document: CompositionTextDocument {
        var committed = ""
        var marked: String?
        var operations: [String] = []
        var unmarkCount: Int { operations.filter { $0 == "unmark" }.count }

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
        writer.select("众筹", remainingReading: "", in: document)
        writer.update("", in: document)
        XCTAssertEqual(document.committed, "众筹")
        XCTAssertNil(document.marked)
        XCTAssertEqual(document.operations, ["mark:ㄓㄨㄥˋ ㄔㄡˊ", "mark:众筹", "unmark"])
    }

    func testSelectingIndividualCharactersDoesNotCommitRawFirstSyllable() {
        let document = Document()
        var writer = CompositionTextWriter()
        writer.update("ㄓㄨㄥˋ ㄔㄡˊ", in: document)
        writer.select("众", remainingReading: "ㄔㄡˊ", in: document)
        writer.update("ㄔㄡˊ", in: document)
        XCTAssertEqual(document.committed, "")
        XCTAssertEqual(document.marked, "众ㄔㄡˊ")
        XCTAssertEqual(document.unmarkCount, 0)
        writer.select("筹", remainingReading: "", in: document)
        XCTAssertEqual(document.committed, "众筹")
        XCTAssertNil(document.marked)
        XCTAssertEqual(document.unmarkCount, 1)
        XCTAssertFalse(document.operations.contains("mark:"))
    }

    func testFourManuallySelectedCharactersStayChineseWithoutAnyWholeWordLookup() {
        let document = Document()
        var writer = CompositionTextWriter()
        writer.update("ㄇㄠ ㄔㄡˊ ㄗˇ ㄓㄠˋ", in: document)
        let steps = [("猫", "ㄔㄡˊ ㄗˇ ㄓㄠˋ", "猫ㄔㄡˊ ㄗˇ ㄓㄠˋ"),
                     ("筹", "ㄗˇ ㄓㄠˋ", "猫筹ㄗˇ ㄓㄠˋ"),
                     ("紫", "ㄓㄠˋ", "猫筹紫ㄓㄠˋ")]
        for (chosen, remaining, expected) in steps {
            writer.select(chosen, remainingReading: remaining, in: document)
            // Mirrors the controller's normal composition refresh after every choice.
            writer.update(remaining, in: document)
            XCTAssertEqual(document.marked, expected)
            XCTAssertEqual(document.unmarkCount, 0)
            XCTAssertEqual(document.committed, "")
        }
        writer.select("罩", remainingReading: "", in: document)
        writer.update("", in: document)
        XCTAssertEqual(document.committed, "猫筹紫罩")
        XCTAssertEqual(document.unmarkCount, 1)
        XCTAssertEqual(writer.selectedText, "")
    }

    func testCommittingTheRemainderIncludesPreviouslySelectedSegments() {
        let document = Document()
        var writer = CompositionTextWriter()
        writer.update("ㄇㄠ ㄔㄡˊ ㄗˇ ㄓㄠˋ", in: document)
        writer.select("猫筹", remainingReading: "ㄗˇ ㄓㄠˋ", in: document)
        writer.commit("紫罩", in: document)
        XCTAssertEqual(document.committed, "猫筹紫罩")
        XCTAssertEqual(document.unmarkCount, 1)
    }

    func testEditingRemainingReadingPreservesSelectedPrefixAndDeletionFinishesIt() {
        let document = Document()
        var writer = CompositionTextWriter()
        writer.update("ㄇㄠ ㄔㄡˊ", in: document)
        writer.select("猫", remainingReading: "ㄔㄡˊ", in: document)
        writer.update("ㄔㄡ", in: document)
        XCTAssertEqual(document.marked, "猫ㄔㄡ")
        writer.update("", in: document)
        XCTAssertEqual(document.committed, "猫")
        XCTAssertEqual(document.unmarkCount, 1)
        writer.select("你", remainingReading: "", in: document)
        XCTAssertEqual(document.committed, "猫你")
    }

    func testResetDoesNotCarrySelectedSegmentsIntoAnotherDocument() {
        let first = Document()
        let second = Document()
        var writer = CompositionTextWriter()
        writer.update("ㄇㄠ ㄔㄡˊ", in: first)
        writer.select("猫", remainingReading: "ㄔㄡˊ", in: first)
        writer.reset()
        writer.update("ㄋㄧˇ", in: second)
        writer.select("你", remainingReading: "", in: second)
        XCTAssertEqual(second.committed, "你")
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
