import SwiftUI

@main
struct NamiApp: App {
    @State private var environment = AppEnvironment()
    @State private var localization = AppLocalization()

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
                .environment(localization)
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
                .environment(localization)
                .tint(AppColor.brand)
        }
        .windowToolbarStyle(.unified)
    }
}
