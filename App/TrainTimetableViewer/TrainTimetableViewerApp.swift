import SwiftUI
import TimetableCore

@main
struct TrainTimetableViewerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(model: model)
        } label: {
            MenuBarLabel(viewModel: model.viewModel)
        }

        Settings {
            SettingsView(model: model)
        }
    }
}
