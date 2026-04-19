import SwiftUI
import Cartographer

@main
struct CartographerDemoApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .task { await container.bootstrap() }
        }
    }
}
