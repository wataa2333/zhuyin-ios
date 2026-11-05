import Foundation
import SQLite3

/// Immutable, indexed on-disk dictionary. No complete word list is materialized in Swift.
final class LexiconDatabase: @unchecked Sendable {
    struct Entry {
        let candidate: Candidate
        let rank: Int
    }

    enum Match: Equatable { case exact, completion }
    enum OpenError: Error { case invalidDatabase }
    private let connection: OpaquePointer

    init(url: URL) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw OpenError.invalidDatabase
        }
        var opened = false
        defer { if !opened { sqlite3_close(handle) } }
        sqlite3_exec(handle, "PRAGMA query_only=ON; PRAGMA cache_size=-512; PRAGMA mmap_size=8388608;", nil, nil, nil)
        var check: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT value FROM metadata WHERE key='format'", -1, &check, nil) == SQLITE_OK else {
            throw OpenError.invalidDatabase
        }
        defer { sqlite3_finalize(check) }
        guard sqlite3_step(check) == SQLITE_ROW, let value = sqlite3_column_text(check, 0),
              String(cString: value) == "zhuyin-sqlite-1" else {
            throw OpenError.invalidDatabase
        }
        connection = handle
        opened = true
    }

    deinit { sqlite3_close(connection) }

    func releaseUnusedMemory() { _ = sqlite3_db_release_memory(connection) }

    func lookup(_ input: [Syllable], match: Match = .exact, limit: Int) -> [Entry] {
        guard !input.isEmpty, limit > 0 else { return [] }
        let sound = Self.soundKey(for: input)
        let completion = match == .completion
        let readingPattern = input.enumerated().map { index, syllable in
            let wildcard = completion && index == input.count - 1 ? "*" : ""
            return syllable.symbols + wildcard + (syllable.tone.map { "[0\($0)]" } ?? "[0-5]")
        }.joined(separator: " ")
        let predicate = completion
            ? "sound_key >= ? AND sound_key < ? AND sound_key <> ?"
            : "sound_key = ?"
        let sql = "SELECT text, reading, rank FROM entries WHERE syllables = ? AND \(predicate) AND reading GLOB ? ORDER BY rank LIMIT ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(input.count))
        // SQLite must copy the temporary UTF-8 buffers used by Swift's bridging.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 2, sound, -1, transient)
        var patternIndex: Int32 = 3
        if completion {
            sqlite3_bind_text(statement, 3, sound + "\u{10FFFF}", -1, transient)
            sqlite3_bind_text(statement, 4, sound, -1, transient)
            patternIndex = 5
        }
        sqlite3_bind_text(statement, patternIndex, readingPattern, -1, transient)
        sqlite3_bind_int(statement, patternIndex + 1, Int32(limit))
        var results: [Entry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0), let reading = sqlite3_column_text(statement, 1),
                  let candidate = Candidate(text: String(cString: text), readingCode: Substring(String(cString: reading))) else { continue }
            results.append(Entry(candidate: candidate, rank: Int(sqlite3_column_int64(statement, 2))))
        }
        return results
    }

    func candidates(for input: [Syllable], allowLastPrefix: Bool) -> [Candidate] {
        var entries = lookup(input, limit: 36)
        if allowLastPrefix { entries += lookup(input, match: .completion, limit: 24) }
        if input.count > 1 {
            let prefixes = (1..<input.count).flatMap { lookup(Array(input.prefix($0)), limit: 24) }
            entries += prefixes.sorted { $0.rank < $1.rank }.prefix(24)
        }
        return entries.map(\.candidate)
    }

    static func soundKey(for input: [Syllable]) -> String {
        input.map { syllable in
            String(syllable.symbols.unicodeScalars.map { scalar -> Character in
                guard (0x3105...0x3129).contains(scalar.value) else { return "?" }
                return Character(UnicodeScalar(scalar.value - 0x3105 + 65)!)
            })
        }.joined(separator: " ")
    }

    func bestMatch(for input: [Syllable], allowLastPrefix: Bool) -> Candidate? {
        if let exact = lookup(input, limit: 1).first { return exact.candidate }
        return allowLastPrefix ? lookup(input, match: .completion, limit: 1).first?.candidate : nil
    }
}
