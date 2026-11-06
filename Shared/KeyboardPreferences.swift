import Foundation
import CoreFoundation

struct KeyFeedbackSettings: Equatable, Sendable {
    var volume: UInt8 = 40
    var haptics: UInt8 = 1

    var data: Data { Data([volume, haptics]) }

    init() {}

    init?(data: Data) {
        guard data.count == 2, let volume = data.first, let haptics = data.last,
              volume <= 100, haptics <= 3 else { return nil }
        self.volume = volume
        self.haptics = haptics
    }
}

enum KeyboardPreferences {
    static let changeNotification = "com.wataa2333.zhuyin.settings.changed"

    static func notifyChanged() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: changeNotification as CFString), nil, nil, true)
    }
    private static let localPinyinKey = "showPinyinOnKeys"
    private static let localFeedbackKey = "keyFeedback"

    private static var sharedDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.wataa2333.zhuyin")
    }

    static var pinyinFile: URL? { sharedDirectory?.appendingPathComponent("pinyin-labels") }
    static var feedbackFile: URL? { sharedDirectory?.appendingPathComponent("key-feedback") }
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

    static var localFeedback: KeyFeedbackSettings {
        UserDefaults.standard.data(forKey: localFeedbackKey).flatMap(KeyFeedbackSettings.init(data:))
            ?? KeyFeedbackSettings()
    }

    static var sharedFeedback: KeyFeedbackSettings? {
        guard let file = feedbackFile, let data = try? Data(contentsOf: file) else { return nil }
        return KeyFeedbackSettings(data: data)
    }

    static func saveLocally(_ feedback: KeyFeedbackSettings) {
        UserDefaults.standard.set(feedback.data, forKey: localFeedbackKey)
    }

    static func syncCode(pinyin: Bool, feedback: KeyFeedbackSettings, layout: KeyboardLayoutConfiguration? = nil) -> String {
        var fields = [pinyin ? "1" : "0", String(feedback.volume), String(feedback.haptics)]
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

    static func syncSettings(from code: String) -> (pinyin: Bool, feedback: KeyFeedbackSettings?, layout: KeyboardLayoutConfiguration?)? {
        if code == "[[Zhuyin-Pinyin:1]]" { return (true, nil, nil) }
        if code == "[[Zhuyin-Pinyin:0]]" { return (false, nil, nil) }
        let prefix = "[[Zhuyin-Settings:"
        guard code.hasPrefix(prefix), code.hasSuffix("]]") else { return nil }
        let fields = code.dropFirst(prefix.count).dropLast(2).split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 3 || fields.count == 9, fields[0] == "0" || fields[0] == "1",
              let volume = UInt8(fields[1]), let haptics = UInt8(fields[2]),
              let feedback = KeyFeedbackSettings(data: Data([volume, haptics])) else { return nil }
        var layout: KeyboardLayoutConfiguration?
        if fields.count == 9 {
            let values = fields.dropFirst(3).compactMap { Double($0) }
            guard values.count == 6 else { return nil }
            let decoded = KeyboardLayoutConfiguration(candidateBarHeight: CGFloat(values[0]), keyHeight: CGFloat(values[1]),
                rowSpacing: CGFloat(values[2]), topInset: CGFloat(values[3]), toolbarSpacing: CGFloat(values[4]),
                bottomInset: CGFloat(values[5]))
            guard decoded.isValid else { return nil }
            layout = decoded
        }
        return (fields[0] == "1", feedback, layout)
    }
}
