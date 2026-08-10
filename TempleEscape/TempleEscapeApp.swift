import SwiftUI

@main
struct TempleEscapeApp: App {
    @StateObject private var viewModel = GameViewModel()

    var body: some Scene {
        WindowGroup {
            ZStack {
                SceneView(viewModel: viewModel)
                    .ignoresSafeArea()
                HUDView(viewModel: viewModel)
            }
            .onAppear {
                // -autostart: skip the menu and drop straight into a run.
                if ProcessInfo.processInfo.arguments.contains("-autostart") {
                    viewModel.start()
                }
            }
            .statusBarHidden(true)
            .preferredColorScheme(.dark)
        }
    }
}
