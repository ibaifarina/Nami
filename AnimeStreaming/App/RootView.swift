import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var contentGeneration = 0

    var body: some View {
        @Bindable var router = environment.router
        ZStack(alignment: .topLeading) {
            detailContent
                .id(contentGeneration)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            SidebarView()

            if environment.playback.isPresenting {
                PlayerView()
                    .environment(environment)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .frame(minWidth: Layout.windowMinWidth, minHeight: Layout.windowMinHeight)
        .containerBackground(AppColor.background, for: .window)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar(removing: .sidebarToggle)
        .animation(.easeOut(duration: Motion.transition), value: environment.playback.isPresenting)
        .task {
            await environment.debridAuth.restore()
        }
        .sheet(
            isPresented: Binding(
                get: { !environment.preferences.hasCompletedOnboarding },
                set: { presented in
                    if !presented {
                        environment.preferences.hasCompletedOnboarding = true
                    }
                }
            )
        ) {
            OnboardingView()
                .environment(environment)
        }
        .task(id: router.refreshToken) {
            guard router.refreshToken > 0 else { return }
            await environment.clearCaches()
            contentGeneration += 1
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        @Bindable var router = environment.router
        switch router.selection ?? .home {
        case .home:
            NavigationStack(path: $router.homePath) {
                HomeView(environment: environment)
                    .navigationDestination(for: AppRouter.Route.self) { route in
                        destination(for: route)
                    }
            }
        case .discover:
            NavigationStack(path: $router.discoverPath) {
                DiscoverView(environment: environment)
                    .navigationDestination(for: AppRouter.Route.self) { route in
                        destination(for: route)
                    }
            }
        case .library:
            NavigationStack(path: $router.libraryPath) {
                LibraryView(environment: environment)
                    .navigationDestination(for: AppRouter.Route.self) { route in
                        destination(for: route)
                    }
            }
        }
    }

    @ViewBuilder
    private func destination(for route: AppRouter.Route) -> some View {
        switch route {
        case .anime(let id):
            AnimeDetailsView(animeID: id, environment: environment)
        }
    }
}
