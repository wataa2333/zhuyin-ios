import Foundation

struct Syllable: Sendable {
    enum Part: Int {
        case initial, medial, final

        init(_ symbol: Character) {
            switch symbol {
            case "ㄅ"..."ㄙ": self = .initial
            case "ㄧ"..."ㄩ": self = .medial
            default: self = .final
            }
        }
    }

    var symbols = ""
    var tone: Character?

    var display: String {
        switch tone {
        case "2": return symbols + "ˊ"
        case "3": return symbols + "ˇ"
        case "4": return symbols + "ˋ"
        case "5": return "˙" + symbols
        default: return symbols
        }
    }

    func matches(_ reading: Syllable, allowPrefix: Bool) -> Bool {
        let sameSound = allowPrefix
            ? reading.symbols.hasPrefix(symbols)
            : reading.symbols == symbols
        return sameSound && (tone == nil || reading.tone == nil || tone == reading.tone)
    }
}

struct Composition {
    private(set) var finished: [Syllable] = []
    private(set) var current = Syllable()
    private(set) var showsFinals = false

    var syllables: [Syllable] {
        current.symbols.isEmpty ? finished : finished + [current]
    }

    var display: String { syllables.map(\.display).joined(separator: " ") }
    var hasInput: Bool { !finished.isEmpty || !current.symbols.isEmpty }

    mutating func togglePage() { showsFinals.toggle() }

    mutating func type(_ symbol: Character) {
        let part = Syllable.Part(symbol)
        if let last = current.symbols.last, part.rawValue <= Syllable.Part(last).rawValue {
            finish()
        }
        current.symbols.append(symbol)
        showsFinals = true
    }

    mutating func finish(tone: Character? = nil) {
        guard !current.symbols.isEmpty else { return }
        current.tone = tone
        finished.append(current)
        current = Syllable()
        showsFinals = false
    }

    mutating func deleteBackward() {
        if current.symbols.isEmpty, let previous = finished.popLast() {
            current = previous
        }
        if current.tone != nil {
            current.tone = nil
        } else {
            _ = current.symbols.popLast()
        }
        if !hasInput { showsFinals = false }
    }

    mutating func consume(_ count: Int) {
        if count >= syllables.count {
            self = Composition()
        } else {
            finished.removeFirst(count)
        }
    }
}

struct Candidate: Sendable {
    let text: String
    let reading: [Syllable]
    let isEmoji: Bool

    init(text: String, reading: [Syllable] = [], isEmoji: Bool = false) {
        self.text = text
        self.reading = reading
        self.isEmoji = isEmoji
    }

    init?(text: String, readingCode: Substring) {
        let reading = readingCode.split(separator: " ").compactMap { code -> Syllable? in
            guard code.count > 1, let tone = code.last, ("0"..."5").contains(tone) else { return nil }
            return Syllable(symbols: String(code.dropLast()), tone: tone == "0" ? nil : tone)
        }
        guard !reading.isEmpty, reading.count == text.count else { return nil }
        self.init(text: text, reading: reading)
    }

    var syllableCount: Int { reading.count }

    var readingCode: String {
        reading.map { $0.symbols + String($0.tone ?? "0") }.joined(separator: " ")
    }
}

struct UserDictionary {
    private struct Record: Codable {
        let text: String
        let readingCode: String
        var uses: Int
    }

    private static let storageKey = "learnedZhuyinWords"
    private let defaults: UserDefaults
    private var records: [Record]
    private var rankedCandidates: [Candidate]?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.storageKey) ?? Data()
        records = (try? JSONDecoder().decode([Record].self, from: saved)) ?? []
    }

    mutating func candidates() -> [Candidate] {
        if let rankedCandidates { return rankedCandidates }
        let ranked = records.enumerated().sorted { left, right in
            if left.element.uses == right.element.uses { return left.offset < right.offset }
            return left.element.uses > right.element.uses
        }.compactMap { record in
            Candidate(text: record.element.text, readingCode: Substring(record.element.readingCode))
        }
        rankedCandidates = ranked
        return ranked
    }

    mutating func learn(_ candidate: Candidate) {
        guard (1...12).contains(candidate.syllableCount),
              candidate.syllableCount == candidate.text.count else { return }
        let code = candidate.readingCode
        let existing = records.firstIndex { $0.text == candidate.text && $0.readingCode == code }
        let uses = existing.map { records.remove(at: $0).uses } ?? 0
        rankedCandidates = nil
        records.insert(Record(text: candidate.text, readingCode: code, uses: min(uses + 1, 10_000)), at: 0)
        if records.count > 256 { records.removeLast(records.count - 256) }
    }

    func save() {
        if let saved = try? JSONEncoder().encode(records) {
            defaults.set(saved, forKey: Self.storageKey)
        }
    }
}

struct Lexicon: Sendable {
    private let database: LexiconDatabase?
    private let entriesByFirstSyllable: [String: [Candidate]]
    private let singleCharactersByPrefix: [String: [Candidate]]

    // The bundled entries are ordered by frequency.
    init(contents: String) {
        database = nil
        var byFirstSyllable: [String: [Candidate]] = [:]
        var singleByPrefix: [String: [Candidate]] = [:]
        for line in contents.split(whereSeparator: \.isNewline) {
            let columns = line.split(separator: "\t")
            guard columns.count == 2,
                  let entry = Candidate(text: String(columns[0]), readingCode: columns[1]),
                  let sound = entry.reading.first?.symbols else { continue }
            byFirstSyllable[sound, default: []].append(entry)
            if entry.syllableCount == 1 {
                for length in 1...sound.count {
                    singleByPrefix[String(sound.prefix(length)), default: []].append(entry)
                }
            }
        }
        entriesByFirstSyllable = byFirstSyllable
        singleCharactersByPrefix = singleByPrefix
    }

    init(databaseURL: URL) throws {
        database = try LexiconDatabase(url: databaseURL)
        entriesByFirstSyllable = [:]
        singleCharactersByPrefix = [:]
    }

    func candidates(for composition: Composition, learned: [Candidate] = []) -> [Candidate] {
        let input = composition.syllables
        guard let first = input.first else { return [] }
        // For phrases, setting the last syllable's tone still allows the remaining symbols to be predicted.
        let canCompleteLast = input.count > 1 || !composition.current.symbols.isEmpty
        var exact: [Candidate] = []
        var completions: [Candidate] = []
        var prefixes: [Candidate] = []

        let builtIn = database?.candidates(for: input, allowLastPrefix: canCompleteLast)
            ?? (input.count == 1
                ? singleCharactersByPrefix[first.symbols, default: []]
                : entriesByFirstSyllable[first.symbols, default: []])
        for entry in [learned, builtIn].joined() {
            let count = entry.reading.count
            guard count <= input.count else { continue }
            let matches = entry.reading.indices.allSatisfy { index in
                input[index].matches(entry.reading[index], allowPrefix: canCompleteLast && index == input.count - 1)
            }
            guard matches else { continue }
            if count < input.count {
                if prefixes.count < 24 { prefixes.append(entry) }
            } else if entry.reading.last?.symbols == input.last?.symbols {
                if exact.count < 36 { exact.append(entry) }
            } else if completions.count < 24 {
                completions.append(entry)
            }
        }

        var ranked = exact + completions
        if ranked.isEmpty, input.count > 1, let phrase = segmentedCandidate(for: input) {
            ranked.append(phrase)
        }
        ranked.append(contentsOf: prefixes)
        var seen: Set<String> = []
        // A lazy filter can evaluate its predicate again when slicing or iterating.
        let unique = ranked.filter { seen.insert($0.text).inserted }
        return Array(unique.prefix(48))
    }

    private func segmentedCandidate(for input: [Syllable]) -> Candidate? {
        // Find the fewest dictionary words that cover each suffix, keeping dictionary order for ties.
        var choices = Array<Candidate?>(repeating: nil, count: input.count)
        var wordCounts = Array(repeating: Int.max, count: input.count + 1)
        wordCounts[input.count] = 0
        for start in input.indices.reversed() {
            let sound = input[start].symbols
            let words: [Candidate]
            if let database, input.count - start > 1 {
                words = (2...(input.count - start)).reversed().compactMap { count in
                    let end = start + count
                    return database.bestMatch(for: Array(input[start..<end]), allowLastPrefix: end == input.count)
                }
            } else {
                words = entriesByFirstSyllable[sound, default: []]
            }
            for word in words where word.syllableCount > 1 {
                let end = start + word.syllableCount
                guard end <= input.count, wordCounts[end] < wordCounts[start] - 1 else { continue }
                guard word.reading.indices.allSatisfy({ index in
                    let position = start + index
                    return input[position].matches(word.reading[index], allowPrefix: position == input.count - 1)
                }) else { continue }
                choices[start] = word
                wordCounts[start] = 1 + wordCounts[end]
                if end == input.count { break }
            }
            if wordCounts[start + 1] < wordCounts[start] - 1,
               let character = bestCharacter(for: input[start], allowPrefix: start == input.count - 1) {
                choices[start] = character
                wordCounts[start] = 1 + wordCounts[start + 1]
            }
        }

        var position = 0
        var text = ""
        var reading: [Syllable] = []
        while position < input.count {
            guard let word = choices[position] else { return nil }
            text += word.text
            reading.append(contentsOf: word.reading)
            position += word.syllableCount
        }
        return Candidate(text: text, reading: reading)
    }

    private func bestCharacter(for syllable: Syllable, allowPrefix: Bool) -> Candidate? {
        if let database { return database.bestMatch(for: [syllable], allowLastPrefix: allowPrefix) }
        let entries = singleCharactersByPrefix[syllable.symbols, default: []]
        var completion: Candidate?
        for entry in entries {
            let reading = entry.reading[0]
            guard syllable.matches(reading, allowPrefix: allowPrefix) else { continue }
            if syllable.symbols == reading.symbols { return entry }
            if completion == nil { completion = entry }
        }
        return completion
    }
}
