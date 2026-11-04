import Foundation

enum KeyboardPreferences {
    private static let localPinyinKey = "showPinyinOnKeys"

    static var pinyinFile: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.wataa2333.zhuyin")?
            .appendingPathComponent("pinyin-labels")
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

    static func syncCode(for enabled: Bool) -> String {
        enabled ? "[[Zhuyin-Pinyin:1]]" : "[[Zhuyin-Pinyin:0]]"
    }

    static func pinyinSetting(from code: String) -> Bool? {
        switch code {
        case syncCode(for: true): return true
        case syncCode(for: false): return false
        default: return nil
        }
    }
}
