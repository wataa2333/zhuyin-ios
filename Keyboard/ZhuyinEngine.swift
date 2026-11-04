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
        case "1": return symbols + " "
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
    let syllableCount: Int
}

struct Lexicon {
    private struct Entry {
        let text: String
        let reading: [Syllable]
    }

    private let entriesByInitial: [Character: [Entry]]

    // The bundled entries are ordered by frequency.
    init(contents: String) {
        var index: [Character: [Entry]] = [:]
        for line in contents.split(whereSeparator: \.isNewline) {
            let columns = line.split(separator: "\t")
            guard columns.count == 2 else { continue }
            let reading = columns[1].split(separator: " ").compactMap { code -> Syllable? in
                guard code.count > 1, let tone = code.last else { return nil }
                return Syllable(symbols: String(code.dropLast()), tone: tone == "0" ? nil : tone)
            }
            guard reading.count == columns[0].count,
                  let initial = reading.first?.symbols.first else { continue }
            index[initial, default: []].append(Entry(text: String(columns[0]), reading: reading))
        }
        entriesByInitial = index
    }

    func candidates(for composition: Composition) -> [Candidate] {
        let input = composition.syllables
        guard let initial = input.first?.symbols.first else { return [] }
        let hasOpenSyllable = !composition.current.symbols.isEmpty
        var exact: [Candidate] = []
        var completions: [Candidate] = []
        var prefixes: [Candidate] = []

        for entry in entriesByInitial[initial, default: []] {
            let count = entry.reading.count
            guard count <= input.count else { continue }
            let matches = entry.reading.indices.allSatisfy { index in
                input[index].matches(entry.reading[index], allowPrefix: hasOpenSyllable && index == input.count - 1)
            }
            guard matches else { continue }
            let candidate = Candidate(text: entry.text, syllableCount: count)
            if count < input.count {
                if prefixes.count < 24 { prefixes.append(candidate) }
            } else if entry.reading.last?.symbols == input.last?.symbols {
                if exact.count < 36 { exact.append(candidate) }
            } else if completions.count < 24 {
                completions.append(candidate)
            }
        }

        var ranked = exact + completions
        if ranked.isEmpty, input.count > 1 {
            let words = input.enumerated().compactMap { index, syllable in
                bestCharacter(for: syllable, allowPrefix: hasOpenSyllable && index == input.count - 1)
            }
            if words.count == input.count {
                ranked.append(Candidate(text: words.joined(), syllableCount: input.count))
            }
        }
        ranked.append(contentsOf: prefixes)
        var seen: Set<String> = []
        return Array(ranked.lazy.filter { seen.insert($0.text).inserted }.prefix(48))
    }

    private func bestCharacter(for syllable: Syllable, allowPrefix: Bool) -> String? {
        guard let initial = syllable.symbols.first else { return nil }
        let entries = entriesByInitial[initial, default: []]
        var completion: String?
        for entry in entries where entry.reading.count == 1 {
            let reading = entry.reading[0]
            guard syllable.matches(reading, allowPrefix: allowPrefix) else { continue }
            if syllable.symbols == reading.symbols { return entry.text }
            if completion == nil { completion = entry.text }
        }
        return completion
    }
}
