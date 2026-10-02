import SwiftUI

@main
struct ThockApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(nsImage: MenuBarIcon.image(model.menuBarState))
        }
        .menuBarExtraStyle(.window)
    }
}
