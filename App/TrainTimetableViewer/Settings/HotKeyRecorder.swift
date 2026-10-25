import AppKit
import Carbon.HIToolbox
import SwiftUI
import TimetableCore

extension HotKeySetting {
    /// 押されたキーから作る。⌘・⌥・⌃ のいずれも含まない組み合わせは `nil`（ほかのアプリの入力を奪わないため）
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .option, .control]).isEmpty,
              let characters = event.charactersIgnoringModifiers, !characters.isEmpty
        else { return nil }

        var carbon: UInt32 = 0
        var symbols = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); symbols += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); symbols += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); symbols += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); symbols += "⌘" }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: carbon, label: symbols + characters.uppercased())
    }

    /// メニュー項目に表示するショートカット
    var keyboardShortcut: KeyboardShortcut? {
        guard let character = label.last?.lowercased().first else { return nil }
        var modifiers: SwiftUI.EventModifiers = []
        if carbonModifiers & UInt32(controlKey) != 0 { modifiers.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { modifiers.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { modifiers.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { modifiers.insert(.command) }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
    }
}

/// ショートカットを記録するボタン。押してから組み合わせを入力する（esc で取り消し）
struct HotKeyRecorder: View {
    let model: AppModel

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Button(isRecording ? "キーを押してください…" : model.hotKeySetting.label) {
                    isRecording ? stopRecording() : startRecording()
                }
                .monospaced()
                if model.hotKeySetting != .default {
                    Button("初期値に戻す") {
                        apply(.default)
                    }
                }
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if !model.isHotKeyRegistered {
                Text("ショートカットを登録できませんでした。別の組み合わせを試してください")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        message = nil
        isRecording = true
        model.suspendHotKey()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            guard let setting = HotKeySetting(event: event) else {
                message = "⌘・⌥・⌃ のいずれかと組み合わせてください"
                return nil
            }
            stopRecording(resume: false)
            apply(setting)
            return nil
        }
    }

    private func stopRecording(resume: Bool = true) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if isRecording && resume {
            model.resumeHotKey()
        }
        isRecording = false
    }

    private func apply(_ setting: HotKeySetting) {
        if model.setHotKey(setting) {
            message = nil
        } else {
            message = "\(setting.label) はほかのアプリが使っているため登録できません"
        }
    }
}
