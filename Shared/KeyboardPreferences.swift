import Foundation
import CoreFoundation

enum KeyboardPreferences {
    static let changeNotification = "com.wataa2333.zhuyin.settings.changed"

    static func notifyChanged() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: changeNotification as CFString), nil, nil, true)
    }
    private static let localPinyinKey = "showPinyinOnKeys"

    private static var sharedDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.wataa2333.zhuyin")
    }

    static var pinyinFile: URL? { sharedDirectory?.appendingPathComponent("pinyin-labels") }
    private static var localLayoutFile: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            .appendingPathComponent(KeyboardLayoutFile.name)
    }

    static var localLayout: KeyboardLayoutConfiguration {
        KeyboardLayoutFile.read(from: localLayoutFile) ?? .defaults
    }

    // Height has one authority in each sandbox. Explicit sync directly overwrites the keyboard's copy.
    static var layout: KeyboardLayoutConfiguration { localLayout }

    static func saveLocally(_ layout: KeyboardLayoutConfiguration) throws {
        try KeyboardLayoutFile.save(layout, to: localLayoutFile)
    }

    static func saveLayout(_ layout: KeyboardLayoutConfiguration) throws {
        try saveLocally(layout)
    }

    static var sharedPinyin: Bool? {
        if let file = pinyinFile, let data = try? Data(contentsOf: file) {
            if data == Data([1]) { return true }
            if data == Data([0]) { return false }
        }
        return nil
    }

    static var showsPinyin: Bool {
        sharedPinyin ?? localPinyin
    }

    static var localPinyin: Bool {
        UserDefaults.standard.bool(forKey: localPinyinKey)
    }

    static func saveLocally(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: localPinyinKey)
    }

    static func syncCode(pinyin: Bool, layout: KeyboardLayoutConfiguration? = nil) -> String {
        var fields = [pinyin ? "1" : "0"]
        if let layout {
            fields += [layout.candidateBarHeight, layout.keyHeight, layout.rowSpacing,
                       layout.topInset, layout.toolbarSpacing, layout.bottomInset].map { String(Double($0)) }
        }
        return "[[Zhuyin-Settings:\(fields.joined(separator: ":"))]]"
    }

    static func syncReply(for code: String, succeeded: Bool = true) -> String {
        // A deterministic request identifier; this is matching, not authentication.
        let token = code.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return "[[Zhuyin-\(succeeded ? "Applied" : "Failed"):\(String(token, radix: 16))]]"
    }

    static func syncSettings(from code: String) -> (pinyin: Bool, layout: KeyboardLayoutConfiguration?)? {
        if code == "[[Zhuyin-Pinyin:1]]" { return (true, nil) }
        if code == "[[Zhuyin-Pinyin:0]]" { return (false, nil) }
        let prefix = "[[Zhuyin-Settings:"
        guard code.hasPrefix(prefix), code.hasSuffix("]]") else { return nil }
        let fields = code.dropFirst(prefix.count).dropLast(2).split(separator: ":", omittingEmptySubsequences: false)
        guard [1, 3, 7, 9].contains(fields.count), fields[0] == "0" || fields[0] == "1" else { return nil }
        var layout: KeyboardLayoutConfiguration?
        // Older sync codes contain two removed options; accept them without restoring those features.
        if fields.count == 7 || fields.count == 9 {
            let values = fields.dropFirst(fields.count == 7 ? 1 : 3).compactMap { Double($0) }
            guard values.count == 6 else { return nil }
            let decoded = KeyboardLayoutConfiguration(candidateBarHeight: CGFloat(values[0]), keyHeight: CGFloat(values[1]),
                rowSpacing: CGFloat(values[2]), topInset: CGFloat(values[3]), toolbarSpacing: CGFloat(values[4]),
                bottomInset: CGFloat(values[5]))
            guard decoded.isValid else { return nil }
            layout = decoded
        }
        return (fields[0] == "1", layout)
    }
}
