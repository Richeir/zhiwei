import os
import SwiftUI

/// 知微 App 入口（PLAN §2.2 `Sources/App`：@main、TabView 壳、DI 组装根）。
///
/// 生命周期约定：
/// - 会话恢复不在此处做网络请求，交由 `RootView.task` 里的 `session.refresh()`（M1 落地）
/// - App 前后台切换会驱动 `WebViewChannel` 的存活检查（R7 判据②），场景相位见 `ScenePhaseObserver`
@main
struct ZhiWeiApp: App {
    @State private var container = AppContainer.live
    @State private var scenePhaseObserver = ScenePhaseObserver()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .environment(scenePhaseObserver)
                .tint(Theme.accent)
        }
    }
}

/// 场景相位观察者：把 SwiftUI 的 `scenePhase` 抬成全局可订阅状态。
///
/// 为什么单独一个对象：R7 判据②要验证「App 前后台切换 / 锁屏恢复后，页面内 fetch 的桥回传是否存活」，
/// 需要通道层能被相位驱动做自检，而 `.onReceive` 不适合散在视图里。
@MainActor
@Observable
final class ScenePhaseObserver {
    private(set) var phase: ScenePhase = .active
    private(set) var backgroundCount: Int = 0

    func update(_ next: ScenePhase) {
        guard next != phase else { return }
        if case .background = next {
            backgroundCount += 1
        }
        Logger.log(domain: .app).info("scenePhase → \(String(describing: next), privacy: .public)")
        phase = next
    }
}
