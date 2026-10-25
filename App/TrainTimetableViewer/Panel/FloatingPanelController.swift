import AppKit
import SwiftUI

/// 他のアプリのフォーカスを奪わずに最前面に表示するパネル（設計書 §6.2）
@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    /// パネルが閉じられたとき（× ボタンなど）
    var onClose: (() -> Void)?

    /// 位置とサイズの保存先（`UserDefaults`）
    private static let frameKey = "panelFrame"
    private static let defaultSize = NSSize(width: 340, height: 240)

    init<Content: View>(rootView: Content) {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        super.init()

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.minSize = NSSize(width: 260, height: 140)
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        // 前回の位置とサイズを復元する。初回や、画面構成が変わってどの画面にも入らない場合は右上に置く。
        // NSWindow の frame autosave は、複数ディスプレイの環境で別の画面に補正されることがあるため使わない
        if let frame = Self.savedFrame() {
            panel.setFrame(frame, display: false)
        } else {
            placeAtTopRight()
        }
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveFrame()
    }

    private func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: Self.frameKey)
    }

    private static func savedFrame() -> NSRect? {
        guard let text = UserDefaults.standard.string(forKey: frameKey) else { return nil }
        let frame = NSRectFromString(text)
        guard frame.width > 0, frame.height > 0,
              NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) })
        else { return nil }
        return frame
    }

    /// メニューバーのある画面の右上に置く
    private func placeAtTopRight() {
        guard let screen = NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.maxX - Self.defaultSize.width - 16,
            y: visible.maxY - Self.defaultSize.height - 16)
        panel.setFrame(NSRect(origin: origin, size: Self.defaultSize), display: false)
    }
}
