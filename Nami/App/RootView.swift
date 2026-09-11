import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentGeneration = 0

    var body: some View {
        @Bindable var router = environment.router
        @Bindable var launcher = environment.playbackLaunch
        ZStack(alignment: .topLeading) {
            ZStack {
                detailContent
                    .id(DetailIdentity(section: selectedSection, generation: contentGeneration))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: Motion.transition),
                value: selectedSection
            )

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
        .toolbar(removing: environment.playback.isPresenting ? .title : nil)
        .windowToolbarFullScreenVisibility(.onHover)
        .toolbarWindowChrome()
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
        .sheet(item: $launcher.pickerRequest, onDismiss: { launcher.pickerDismissed() }) { request in
            StreamSelectionView(request: request, environment: environment)
        }
        .task(id: router.refreshToken) {
            guard router.refreshToken > 0 else { return }
            await environment.clearCaches()
            contentGeneration += 1
        }
    }

    private var selectedSection: AppRouter.SidebarItem {
        environment.router.selection ?? .home
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
                .navigationBarBackButtonHidden(environment.playback.isPresenting)
        }
    }
}

private struct DetailIdentity: Hashable {
    let section: AppRouter.SidebarItem
    let generation: Int
}

private struct ToolbarWindowChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.toolbar {
                ToolbarItem(placement: .automatic) {
                    Color.clear.frame(width: 1, height: 1)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        } else {
            content
        }
    }
}

private extension View {
    func toolbarWindowChrome() -> some View {
        modifier(ToolbarWindowChrome())
    }
}
