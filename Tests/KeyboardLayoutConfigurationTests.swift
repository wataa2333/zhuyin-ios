import Foundation
import XCTest

final class KeyboardLayoutConfigurationTests: XCTestCase {
    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent(KeyboardLayoutFile.name)
    }

    func testSavedProfileSurvivesRepeatedReadsAndReplacement() throws {
        let file = try temporaryFile()
        var layout = KeyboardLayoutConfiguration.defaults
        layout.candidateBarHeight = 60
        layout.keyHeight = 48
        layout.rowSpacing = 12
        layout.topInset = 20
        layout.toolbarSpacing = 4
        layout.bottomInset = 8
        try KeyboardLayoutFile.save(layout, to: file)
        for _ in 0..<10 { XCTAssertEqual(KeyboardLayoutFile.read(from: file), layout) }
        XCTAssertEqual(layout.keyAreaHeight, 228)
        XCTAssertEqual(layout.candidatePanelHeight, 292)
        XCTAssertEqual(layout.contentHeight, 320)
        try KeyboardLayoutFile.save(.defaults, to: file)
        XCTAssertEqual(KeyboardLayoutFile.read(from: file), .defaults)
    }

    func testInvalidWriteCannotReplaceTheLastUsableProfile() throws {
        let file = try temporaryFile()
        try KeyboardLayoutFile.save(.defaults, to: file)
        let before = try Data(contentsOf: file)
        var invalid = KeyboardLayoutConfiguration.defaults
        invalid.candidateBarHeight = 0
        XCTAssertThrowsError(try KeyboardLayoutFile.save(invalid, to: file))
        XCTAssertEqual(try Data(contentsOf: file), before)
        invalid = .defaults
        invalid.keyHeight = .infinity
        XCTAssertThrowsError(try KeyboardLayoutFile.save(invalid, to: file))
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    func testMissingOrDamagedFileDoesNotBecomeAPartialProfile() throws {
        let file = try temporaryFile()
        XCTAssertNil(KeyboardLayoutFile.read(from: file))
        try Data("{\"candidateBarHeight\":60}".utf8).write(to: file)
        XCTAssertNil(KeyboardLayoutFile.read(from: file))
        try Data("not-json".utf8).write(to: file)
        XCTAssertNil(KeyboardLayoutFile.read(from: file))
    }

    func testManualSyncTransfersAllDimensionsAndKeepsOldCodesCompatible() throws {
        var layout = KeyboardLayoutConfiguration.defaults
        layout.candidateBarHeight = 56
        layout.bottomInset = 12
        let feedback = KeyFeedbackSettings()
        let code = KeyboardPreferences.syncCode(pinyin: true, feedback: feedback, layout: layout)
        XCTAssertLessThanOrEqual(code.count, 64, "Must fit the text proxy's short surrounding context")
        let decoded = try XCTUnwrap(KeyboardPreferences.syncSettings(from: code))
        XCTAssertTrue(decoded.pinyin)
        XCTAssertEqual(decoded.feedback, feedback)
        XCTAssertEqual(decoded.layout, layout)
        let legacy = try XCTUnwrap(KeyboardPreferences.syncSettings(from:
            KeyboardPreferences.syncCode(pinyin: false, feedback: feedback)))
        XCTAssertFalse(legacy.pinyin)
        XCTAssertNil(legacy.layout)
        XCTAssertNil(KeyboardPreferences.syncSettings(from: code.replacingOccurrences(of: ":56.0:", with: ":0.0:")))
    }

    func testReceiptMatchesOnlyTheSettingsRequestThatWasApplied() {
        let first = KeyboardPreferences.syncCode(pinyin: true, feedback: KeyFeedbackSettings(), layout: .defaults)
        var layout = KeyboardLayoutConfiguration.defaults
        layout.candidateBarHeight = 60
        let second = KeyboardPreferences.syncCode(pinyin: true, feedback: KeyFeedbackSettings(), layout: layout)
        XCTAssertEqual(KeyboardPreferences.syncReply(for: first), KeyboardPreferences.syncReply(for: first))
        XCTAssertNotEqual(KeyboardPreferences.syncReply(for: first), KeyboardPreferences.syncReply(for: second))
        XCTAssertNotEqual(KeyboardPreferences.syncReply(for: first), KeyboardPreferences.syncReply(for: first, succeeded: false))
        XCTAssertNil(KeyboardPreferences.syncSettings(from: KeyboardPreferences.syncReply(for: first)))
    }
}
