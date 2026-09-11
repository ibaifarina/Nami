import SwiftUI

struct AppCommands: Commands {
    let router: AppRouter

    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Home") {
                router.select(.home)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Discover") {
                router.select(.discover)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Library") {
                router.select(.library)
            }
            .keyboardShortcut("3", modifiers: .command)

            Divider()

            Button("Search") {
                router.select(.discover)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Refresh") {
                router.requestRefresh()
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}
