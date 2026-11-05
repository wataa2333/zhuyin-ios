import Foundation
import CoreFoundation

final class KeyboardSettingsObserver {
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(), { _, pointer, _, _, _ in
                guard let pointer else { return }
                let observer = Unmanaged<KeyboardSettingsObserver>.fromOpaque(pointer).takeUnretainedValue()
                DispatchQueue.main.async { [weak observer] in observer?.onChange() }
            }, KeyboardPreferences.changeNotification as CFString, nil, .deliverImmediately)
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque())
    }
}
