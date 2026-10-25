import SwiftUI
import TimetableCore

@main
struct TrainTimetableViewerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        // 常駐アプリ（LSUIElement）。メニューバーの表示は #10 で実装する
        MenuBarExtra("Train Timetable Viewer", systemImage: "tram") {
            Text(model.viewModel.menuBarTitle)
            Divider()
            Button("終了") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
