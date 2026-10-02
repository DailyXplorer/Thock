import SwiftUI

@main
struct ThockApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            if let style = MenuBarIcon.Style.selected {
                Image(nsImage: MenuBarIcon.image(style, model.menuBarState))
            } else {
                Image(systemName: model.menuBarSymbol)
                    .accessibilityLabel("Thock")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
