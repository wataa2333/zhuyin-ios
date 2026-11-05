import Foundation
import XCTest

final class ZhuyinEngineTests: XCTestCase {
    private func bundledLexicon() throws -> Lexicon {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Lexicon", withExtension: "sqlite"))
        return try Lexicon(databaseURL: url)
    }

    private func zhongchou(tones: Bool, incompleteLast: Bool = false) -> Composition {
        var composition = Composition()
        for symbol in "ㄓㄨㄥ" { composition.type(symbol) }
        composition.finish(tone: tones ? "4" : nil)
        for symbol in incompleteLast ? "ㄔ" : "ㄔㄡ" { composition.type(symbol) }
        if tones, !incompleteLast { composition.finish(tone: "2") }
        return composition
    }

    func testCrowdfundingIsAvailableWithAndWithoutExplicitTones() throws {
        let lexicon = try bundledLexicon()
        for tones in [false, true] {
            let words = lexicon.candidates(for: zhongchou(tones: tones))
            XCTAssertEqual(words.first?.text, "众筹")
            XCTAssertEqual(words.first?.readingCode, "ㄓㄨㄥ4 ㄔㄡ2")
        }
    }

    func testReadOnlyDictionaryStillWorksAfterMemoryPressureCacheRelease() throws {
        let lexicon = try bundledLexicon()
        lexicon.releaseUnusedMemory()
        XCTAssertEqual(lexicon.candidates(for: zhongchou(tones: true)).first?.text, "众筹")
    }

    func testCrowdfundingCompletesLastSyllableAndStillAllowsPartialSelection() throws {
        let lexicon = try bundledLexicon()
        XCTAssertTrue(lexicon.candidates(for: zhongchou(tones: true, incompleteLast: true))
            .contains { $0.text == "众筹" })
        var input = zhongchou(tones: true)
        XCTAssertTrue(lexicon.candidates(for: input).contains { $0.text == "众" })
        input.consume(1)
        XCTAssertEqual(input.display, "ㄔㄡˊ")
        XCTAssertTrue(lexicon.candidates(for: input).contains { $0.text == "筹" })
    }

    func testKnownWrongToneIsRejectedAndUnknownToneRemainsSelectable() {
        XCTAssertFalse(Syllable(symbols: "ㄓㄨㄥ", tone: "4")
            .matches(Syllable(symbols: "ㄓㄨㄥ", tone: "1"), allowPrefix: false))
        XCTAssertTrue(Syllable(symbols: "ㄓㄨㄥ", tone: "4")
            .matches(Syllable(symbols: "ㄓㄨㄥ", tone: nil), allowPrefix: false))
        XCTAssertEqual(LexiconDatabase.soundKey(for: [Syllable(symbols: "ㄓㄨㄥ"), Syllable(symbols: "ㄔㄡ")]), "Oda P]")
    }
}
