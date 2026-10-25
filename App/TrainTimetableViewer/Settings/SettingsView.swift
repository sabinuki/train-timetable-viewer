import SwiftUI

/// 設定画面（設計書 §6.3）。項目が増えたためタブに分ける
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            RouteSettingsView(model: model)
                .tabItem { Label("路線", systemImage: "tram") }
            PanelSettingsView(model: model)
                .tabItem { Label("パネル", systemImage: "macwindow") }
            GeneralSettingsView(model: model)
                .tabItem { Label("一般", systemImage: "gearshape") }
        }
        .frame(width: 500)
    }
}

/// 設定画面で使うエラー表示
struct SettingsError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

extension View {
    func settingsErrorAlert(_ error: Binding<SettingsError?>) -> some View {
        alert(error.wrappedValue?.title ?? "", isPresented: Binding(
            get: { error.wrappedValue != nil },
            set: { if !$0 { error.wrappedValue = nil } }
        )) {
            Button("OK") { error.wrappedValue = nil }
        } message: {
            Text(error.wrappedValue?.message ?? "")
        }
    }
}
