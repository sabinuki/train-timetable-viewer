import SwiftUI
import TimetableCore

/// メニューバーに常時表示するラベル（例: 🚃 18:05 あと12分）
struct MenuBarLabel: View {
    let viewModel: DepartureBoardViewModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "tram.fill")
            if !viewModel.menuBarTitle.isEmpty {
                Text(viewModel.menuBarTitle)
                    .monospacedDigit()
            }
        }
    }
}
