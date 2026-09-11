import SwiftUI

@main
struct AnimeStreamingApp: App {
    @State private var environment = AppEnvironment()

    init() {
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024
        )
        UserDefaults.standard.register(defaults: [
            "NSSplitViewItemSidebarDefaultsToFloatingAppearance": false
        ])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .tint(AppColor.brand)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands(router: environment.router)
        }

        Settings {
            SettingsScene()
                .environment(environment)
                .tint(AppColor.brand)
        }
    }
}
