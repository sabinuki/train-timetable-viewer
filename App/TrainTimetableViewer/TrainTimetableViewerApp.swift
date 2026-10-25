import SwiftUI
import TimetableCore

@main
struct TrainTimetableViewerApp: App {
    var body: some Scene {
        // 常駐アプリ（LSUIElement）。メニューバーの表示は #10 で実装する
        MenuBarExtra("Train Timetable Viewer", systemImage: "tram") {
            Button("終了") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
