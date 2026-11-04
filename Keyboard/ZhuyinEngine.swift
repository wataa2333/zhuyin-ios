import Foundation

struct Syllable {
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
        return sameSound && (tone == nil || tone == reading.tone)
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
        showsFinals = !current.symbols.isEmpty
    }

    mutating func consume(_ count: Int) {
        if count >= syllables.count {
            self = Composition()
        } else {
            finished.removeFirst(count)
        }
    }
}

struct Candidate {
    let text: String
    let reading: [Syllable]

    init(text: String, reading: [Syllable] = []) {
        self.text = text
        self.reading = reading
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.storageKey) ?? Data()
        records = (try? JSONDecoder().decode([Record].self, from: saved)) ?? []
    }

    var candidates: [Candidate] {
        records.enumerated().sorted { left, right in
            if left.element.uses == right.element.uses { return left.offset < right.offset }
            return left.element.uses > right.element.uses
        }.compactMap { record in
            Candidate(text: record.element.text, readingCode: Substring(record.element.readingCode))
        }
    }

    mutating func learn(_ candidate: Candidate) {
        guard (1...12).contains(candidate.syllableCount),
              candidate.syllableCount == candidate.text.count else { return }
        let code = candidate.readingCode
        let existing = records.firstIndex { $0.text == candidate.text && $0.readingCode == code }
        let uses = existing.map { records.remove(at: $0).uses } ?? 0
        records.insert(Record(text: candidate.text, readingCode: code, uses: min(uses + 1, 10_000)), at: 0)
        if records.count > 256 { records.removeLast(records.count - 256) }
        if let saved = try? JSONEncoder().encode(records) {
            defaults.set(saved, forKey: Self.storageKey)
        }
    }
}

struct Lexicon {
    private let entriesByInitial: [Character: [Candidate]]

    // The bundled entries are ordered by frequency.
    init(contents: String) {
        var index: [Character: [Candidate]] = [:]
        for line in contents.split(whereSeparator: \.isNewline) {
            let columns = line.split(separator: "\t")
            guard columns.count == 2,
                  let entry = Candidate(text: String(columns[0]), readingCode: columns[1]),
                  let initial = entry.reading.first?.symbols.first else { continue }
            index[initial, default: []].append(entry)
        }
        entriesByInitial = index
    }

    func candidates(for composition: Composition, learned: [Candidate] = []) -> [Candidate] {
        let input = composition.syllables
        guard let initial = input.first?.symbols.first else { return [] }
        let hasOpenSyllable = !composition.current.symbols.isEmpty
        var exact: [Candidate] = []
        var completions: [Candidate] = []
        var prefixes: [Candidate] = []

        let personal = learned.filter { $0.reading.first?.symbols.first == initial }
        for entry in [personal, entriesByInitial[initial, default: []]].joined() {
            let count = entry.reading.count
            guard count <= input.count else { continue }
            let matches = entry.reading.indices.allSatisfy { index in
                input[index].matches(entry.reading[index], allowPrefix: hasOpenSyllable && index == input.count - 1)
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
        if ranked.isEmpty, input.count > 1 {
            let words = input.enumerated().compactMap { index, syllable in
                bestCharacter(for: syllable, allowPrefix: hasOpenSyllable && index == input.count - 1)
            }
            if words.count == input.count {
                ranked.append(Candidate(text: words.map(\.text).joined(), reading: words.flatMap(\.reading)))
            }
        }
        ranked.append(contentsOf: prefixes)
        var seen: Set<String> = []
        // A lazy filter can evaluate its predicate again when slicing or iterating.
        let unique = ranked.filter { seen.insert($0.text).inserted }
        return Array(unique.prefix(48))
    }

    private func bestCharacter(for syllable: Syllable, allowPrefix: Bool) -> Candidate? {
        guard let initial = syllable.symbols.first else { return nil }
        let entries = entriesByInitial[initial, default: []]
        var completion: Candidate?
        for entry in entries where entry.reading.count == 1 {
            let reading = entry.reading[0]
            guard syllable.matches(reading, allowPrefix: allowPrefix) else { continue }
            if syllable.symbols == reading.symbols { return entry }
            if completion == nil { completion = entry }
        }
        return completion
    }
}
