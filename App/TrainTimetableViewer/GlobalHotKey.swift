import Carbon.HIToolbox
import os
import TimetableCore

/// 他のアプリを操作中でも反応するグローバルショートカット。
/// Carbon の `RegisterEventHotKey` を使うため、アクセシビリティ権限は不要
@MainActor
final class GlobalHotKey {
    private var keyCode: UInt32
    private var modifiers: UInt32
    private let action: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private static let logger = Logger(subsystem: "com.sabinuki.TrainTimetableViewer", category: "GlobalHotKey")
    /// 'TTVH'
    private static let signature = OSType(0x5454_5648)

    init(setting: HotKeySetting, action: @escaping @MainActor () -> Void) {
        self.keyCode = setting.keyCode
        self.modifiers = setting.carbonModifiers
        self.action = action
    }

    /// キーの組み合わせを変えて登録し直す
    @discardableResult
    func update(_ setting: HotKeySetting) -> Bool {
        keyCode = setting.keyCode
        modifiers = setting.carbonModifiers
        return register()
    }

    /// 登録する。ほかのアプリが同じ組み合わせを使っている場合などは false
    @discardableResult
    func register() -> Bool {
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        let succeeded = installStatus == noErr && registerStatus == noErr
        if succeeded {
            Self.logger.notice("グローバルショートカットを登録しました（keyCode: \(self.keyCode), modifiers: \(self.modifiers)）")
        } else {
            Self.logger.error("グローバルショートカットを登録できません（install: \(installStatus), register: \(registerStatus)）")
            unregister()
        }
        return succeeded
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}
