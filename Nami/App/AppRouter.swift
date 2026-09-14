import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
        case home
        case discover
        case library

        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: String(localized: "Home")
            case .discover: String(localized: "Discover")
            case .library: String(localized: "Library")
            }
        }

        func systemImage(isSelected: Bool) -> String {
            switch self {
            case .home:
                isSelected ? "house.fill" : "house"
            case .discover:
                "magnifyingglass"
            case .library:
                isSelected ? "bookmark.fill" : "bookmark"
            }
        }
    }

    enum Route: Hashable {
        case anime(id: String)
    }

    var selection: SidebarItem? = .home
    var homePath: [Route] = []
    var discoverPath: [Route] = []
    var libraryPath: [Route] = []
    var refreshToken = 0

    func select(_ item: SidebarItem) {
        selection = item
        resetPath(for: item)
    }

    private func resetPath(for item: SidebarItem) {
        switch item {
        case .home: homePath.removeAll()
        case .discover: discoverPath.removeAll()
        case .library: libraryPath.removeAll()
        }
    }

    func requestRefresh() {
        refreshToken += 1
    }

    func push(_ route: Route, in section: SidebarItem) {
        switch section {
        case .home: homePath.append(route)
        case .discover: discoverPath.append(route)
        case .library: libraryPath.append(route)
        }
    }
}
