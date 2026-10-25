import Carbon.HIToolbox
import os

/// 他のアプリを操作中でも反応するグローバルショートカット。
/// Carbon の `RegisterEventHotKey` を使うため、アクセシビリティ権限は不要
@MainActor
final class GlobalHotKey {
    /// 初期値は ⌥⌘T。変更は #20 で設定画面に追加する
    nonisolated static let defaultKeyCode = UInt32(kVK_ANSI_T)
    nonisolated static let defaultModifiers = UInt32(optionKey | cmdKey)

    private let keyCode: UInt32
    private let modifiers: UInt32
    private let action: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private static let logger = Logger(subsystem: "com.sabinuki.TrainTimetableViewer", category: "GlobalHotKey")
    /// 'TTVH'
    private static let signature = OSType(0x5454_5648)

    init(
        keyCode: UInt32 = GlobalHotKey.defaultKeyCode,
        modifiers: UInt32 = GlobalHotKey.defaultModifiers,
        action: @escaping @MainActor () -> Void
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action
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
            Self.logger.info("グローバルショートカットを登録しました")
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
