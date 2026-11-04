import Foundation

@main
struct CheckCandidates {
    static func main() throws {
        let dictionary = try String(contentsOfFile: "Keyboard/Lexicon.tsv", encoding: .utf8)
        let lexicon = Lexicon(contents: dictionary)

        var input = Composition()
        input.type("ㄒ")
        let prefix = lexicon.candidates(for: input)
        precondition(prefix.contains { $0.text == "想" }, "ㄒ must show character candidates")
        precondition(Set(prefix.map(\.text)).count == prefix.count, "Candidates must be unique")

        input.type("ㄧ")
        input.type("ㄝ")
        input.finish(tone: "4")
        for symbol in "ㄒㄧㄝ" { input.type(symbol) }
        input.finish(tone: "5")
        precondition(lexicon.candidates(for: input).first?.text == "谢谢", "The complete reading must match 谢谢")

        let domain = "ZhuyinCandidateCheck.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: domain) else {
            preconditionFailure("Could not open test preferences")
        }
        defer { defaults.removePersistentDomain(forName: domain) }
        var personal = UserDictionary(defaults: defaults)
        personal.learn(Candidate(text: "谢蟹", reading: input.syllables))
        let restored = UserDictionary(defaults: defaults)
        let learned = lexicon.candidates(for: input, learned: restored.candidates)
        precondition(learned.first?.text == "谢蟹", "A saved personal word must outrank built-in matches")
    }
}
