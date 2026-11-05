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

    static func syncCode(pinyin: Bool, feedback: KeyFeedbackSettings) -> String {
        "[[Zhuyin-Settings:\(pinyin ? 1 : 0):\(feedback.volume):\(feedback.haptics)]]"
    }

    static func syncSettings(from code: String) -> (pinyin: Bool, feedback: KeyFeedbackSettings?)? {
        if code == "[[Zhuyin-Pinyin:1]]" { return (true, nil) }
        if code == "[[Zhuyin-Pinyin:0]]" { return (false, nil) }
        let prefix = "[[Zhuyin-Settings:"
        guard code.hasPrefix(prefix), code.hasSuffix("]]") else { return nil }
        let fields = code.dropFirst(prefix.count).dropLast(2).split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 3, fields[0] == "0" || fields[0] == "1",
              let volume = UInt8(fields[1]), let haptics = UInt8(fields[2]),
              let feedback = KeyFeedbackSettings(data: Data([volume, haptics])) else { return nil }
        return (fields[0] == "1", feedback)
    }
}
