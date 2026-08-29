import SwiftUI
import WebKit

// MARK: - 登录窗口（PLAN M1「sheet 内嵌可见 WKWebView 打开微博扫码登录页，用户人工完成，
// App 全程不接触账密」）
//
// M0 交付：可见登录 WebView + "完成"手势 + 本地 cookie 观察（判据③ 的人工配合环节）。
// M1 补：挑战页复用、多端互踢提示、登录成功后的 profile 回灌。

/// 登录页地址：Web 端统一登录（含扫码 / 短信 / 账密三种入口，由用户在页面里自选）
enum LoginTarget {
    static let url = URL(string: "https://passport.weibo.com/qrlogin/generate?entry=weibo&return_url=https%3A%2F%2Fweibo.com")!
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
                .task { await watchCookies() }
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

    /// 轮询本地 cookie 存储（只读系统 WebKit，不发网络请求，因此不占限流预算）
    private func watchCookies() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        while !Task.isCancelled, observing {
            let cookies = await CookieBridge.allCookies(from: store)
            if CookieBridge.hasLoginCookies(cookies) {
                detected = true
                observing = false
                return
            }
            try? await Task.sleep(for: .seconds(2))
        }
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
