import SwiftUI

/// 导航壳（PLAN §5「导航壳：`TabView` + 各 tab 内 `NavigationStack`，集中 Route enum」）。
///
/// M0 只要壳与视觉基线定样；各 tab 的真实内容随 M2+ 填充。
struct RootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(ScenePhaseObserver.self) private var scenePhaseObserver
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: Tab = .timeline
    @State private var timelinePath: [Route] = []
    @State private var searchPath: [Route] = []
    @State private var notificationPath: [Route] = []
    @State private var profilePath: [Route] = []
    @State private var composing = false

    var body: some View {
        TabView(selection: $tab) {
            TimelineHomeView(path: $timelinePath)
                .tabItem { Label(Tab.timeline.title, systemImage: Tab.timeline.systemImage) }
                .tag(Tab.timeline)

            SearchHomeView(path: $searchPath)
                .tabItem { Label(Tab.search.title, systemImage: Tab.search.systemImage) }
                .tag(Tab.search)

            NotificationsHomeView(path: $notificationPath)
                .tabItem { Label(Tab.notifications.title, systemImage: Tab.notifications.systemImage) }
                .badge(0) // M7：未读数由轮询驱动
                .tag(Tab.notifications)

            ProfileHomeView(path: $profilePath)
                .tabItem { Label(Tab.profile.title, systemImage: Tab.profile.systemImage) }
                .tag(Tab.profile)
        }
        .overlay(alignment: .bottomTrailing) { composeButton }
        .sheet(isPresented: $composing) { ComposeView(isPresented: $composing) }
        .environment(\.appNavigator, AppNavigator(
            selectTab: { tab = $0 },
            push: { route in
                switch tab {
                case .timeline: timelinePath.append(route)
                case .search: searchPath.append(route)
                case .notifications: notificationPath.append(route)
                case .profile: profilePath.append(route)
                }
            }))
        .onChange(of: scenePhase, initial: true) { _, next in
            scenePhaseObserver.update(next)
        }
    }

    /// 浮动发博按钮（PLAN D7：毛玻璃是系统语言而非自建效果；M2 用 `glassEffectID` 做形变转场）
    private var composeButton: some View {
        GlassSurface(id: "compose") {
            Button {
                composing = true
            } label: {
                Image(systemName: "feather")
                    .font(.title3.weight(.semibold))
                    .accessibilityLabel("发微博")
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("composeButton")
        }
        .padding(.trailing, Theme.gutter)
        .padding(.bottom, Theme.gutter)
    }
}

/// 跨 tab / 深层跳转的注入点，避免把 binding 一路透传到叶子视图。
struct AppNavigator {
    let selectTab: (Tab) -> Void
    let push: (Route) -> Void

    func go(_ appRoute: AppRoute) {
        switch appRoute {
        case .openTab(let tab): selectTab(tab)
        case .to(let route): push(route)
        }
    }
}

extension EnvironmentValues {
    @Entry var appNavigator: AppNavigator = AppNavigator(selectTab: { _ in }, push: { _ in })
}
