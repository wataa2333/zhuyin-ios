import Foundation

enum KeyboardPreferences {
    static var pinyinFile: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.wataa2333.zhuyin")?
            .appendingPathComponent("pinyin-labels")
    }

    static var showsPinyin: Bool {
        guard let file = pinyinFile else { return false }
        return (try? Data(contentsOf: file)) == Data([1])
    }
}
