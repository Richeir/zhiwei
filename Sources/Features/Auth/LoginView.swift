import SwiftUI
import WebKit

// MARK: - 登录窗口（PLAN M1「sheet 内嵌可见 WKWebView 打开微博扫码登录页，用户人工完成，
// App 全程不接触账密」）
//
// M0 交付：可见登录 WebView + "完成"手势 + 本地 cookie 观察（判据③ 的人工配合环节）。
// M1 补：挑战页复用、多端互踢提示、登录成功后的 profile 回灌。

/// 登录页地址：移动站统一登录（账密 / 短信 / 扫码，由用户在页面里自选），
/// 登录后回跳 m.weibo.cn，与车道① 同源入口保持一致。
enum LoginTarget {
    static let url =
        URL(
            string: "https://passport.weibo.com/sso/signin?entry=wapsso&source=wapsso&url=https%3A%2F%2Fm.weibo.cn%2F%3Fjumpfrom%3Dweibocom")!
}

/// 可见登录 WebView 的 UIKit 桥（PLAN D1：个别交互下沉 UIKit）
struct LoginWebView: UIViewRepresentable {
    var url: URL = LoginTarget.url

    func makeUIView(context _: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 关键：用默认存储，登录成功后 cookie 直接进系统 WebKit CookieJar（§5 凭证红线的正解）
        config.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = true
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_: WKWebView, context _: Context) {}
}

struct LoginView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var observing = true
    @State private var detected = false

    var body: some View {
        NavigationStack {
            LoginWebView()
                .ignoresSafeArea(edges: .bottom)
                .overlay {
                    if detected {
                        // 观察到登录 cookie 后不自动关窗：让用户确认页面已正常进入（防误判）
                        ConfirmationBanner { finish() }
                    }
                }
                .safeAreaInset(edge: .bottom) { footer }
                .navigationTitle("登录微博")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                }
                .task { await watchLogin() }
        }
    }

    private var footer: some View {
        GlassSurface {
            VStack(spacing: 6) {
                Text("凭证只存在于系统 WebKit，App 不读取、不保存")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                Button("我已完成登录", action: finish)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
            .padding(.horizontal, 4)
        }
        .padding(.bottom, 8)
    }

    /// 登录成功判定：以 m 站探测的**有效性**为准，而不是“cookie 名字是否存在”。
    /// 旧会话残留的 cookie 只满足名字判定，会让登录页一打开就误报“检测到登录”；
    /// 用 `probeSession`（m 站 config）验证真实登录态可消除这类假阳性。
    private func watchLogin() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        // 进入即验证：旧会话若仍有效，直接放行回首页（免重登），不打扰用户
        if await probeLoggedIn() {
            finish()
            return
        }
        while !Task.isCancelled, observing {
            let cookies = await CookieBridge.allCookies(from: store)
            // 粗筛（登录 cookie 名齐）后再做有效性验证，避免反复探测、也避免残留无效 cookie 误判
            if CookieBridge.hasLoginCookies(cookies), await probeLoggedIn() {
                // 服务端确认登录 → 自动关窗回首页（检测已可靠，不再要用户手动点“继续”）
                observing = false
                finish()
                return
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    /// 走一次会话探测判断是否真的已登录（探测经限流 actor，间隔安全）
    private func probeLoggedIn() async -> Bool {
        await (try? container.channel.probeSession())?.isLoggedIn ?? false
    }

    private func finish() {
        observing = false
        Task {
            await container.session.probe(using: container.channel)
            dismiss()
        }
    }
}

private struct ConfirmationBanner: View {
    var confirm: () -> Void

    var body: some View {
        VStack {
            GlassSurface {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    Text("检测到登录状态").font(.subheadline)
                    Button("继续", action: confirm).buttonStyle(.borderless)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundStyle(Theme.muted)
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            Spacer()
        }
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// 风控人工验证页（R1 缓解措施③ / §5 风控降级链路第 2 步）。
///
/// 通道的 `presentVerification` 只负责把状态推到这里；验证完成后调用
/// `WebViewChannelLive.resumeAfterVerification()`，被挂住的请求自动重放。
struct VerificationView: View {
    let challenge: PunishChallenge
    var onFinish: () -> Void

    var body: some View {
        NavigationStack {
            LoginWebView(url: challenge.url)
                .navigationTitle("需要你的确认")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("我已完成验证") {
                            onFinish()
                        }
                    }
                }
        }
    }
}
