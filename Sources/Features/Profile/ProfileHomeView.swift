import SwiftUI

// MARK: - 「我的」tab（M5 的个人主页在此；未登录时它同时是登录入口）

struct ProfileHomeView: View {
    @Binding var path: [Route]
    @Environment(AppContainer.self) private var container

    @State private var showLogin = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    header
                }
                Section("微博") {
                    Label("我的微博", systemImage: "text.alignleft")
                    Label("草稿箱", systemImage: "tray.and.arrow.down")
                        .badge(draftCount)
                }
                Section("设置") {
                    NavigationLink { SettingsView() } label: {
                        Label("通用与数据", systemImage: "gearshape")
                    }
                    #if DEBUG
                        NavigationLink { R7SpikeView() } label: {
                            Label("R7 通道判据自检", systemImage: "stethoscope")
                        }
                    #endif
                    Button("退出登录", role: .destructive) {
                        Task { await container.session.signOut() }
                    }
                }
            }
            .navigationTitle("我的")
            .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
            .sheet(isPresented: $showLogin) { LoginView() }
        }
    }

    private var draftCount: Int {
        DraftStore(store: container.store).all().count
    }

    @ViewBuilder
    private var header: some View {
        switch container.session.status {
        case .signedIn(let user):
            HStack(spacing: 12) {
                AvatarView(url: user.avatarURL, side: 56, verifiedType: user.verifiedType)
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.screenName).font(.headline)
                    if user.statusCount > 0 {
                        Text("\(user.statusCount) 微博 · \(user.follows) 关注 · \(user.followers) 粉丝")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                Button("编辑资料") { path.append(.userProfile(uid: user.id)) }
                    .buttonStyle(.glass)
                    .font(.footnote)
            }
            .padding(.vertical, 6)
        case .probing:
            HStack { ProgressView()
                Text("检查登录状态…").foregroundStyle(Theme.muted)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("未登录").font(.headline)
                Text("凭证只存系统 WebKit，App 不接触账密")
                    .font(.caption).foregroundStyle(Theme.muted)
                Button("登录微博") { showLogin = true }
                    .buttonStyle(.glassProminent)
            }
            .padding(.vertical, 6)
        }
    }
}

/// 设置页（M0 只放有实际作用的两项，其余等真需求再加）
struct SettingsView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        List {
            Section("数据与低调（R1）") {
                Stepper(value: staleSeconds) {
                    HStack {
                        Text("时间线缓存时长")
                        Spacer()
                        Text("\(Int(staleSeconds.wrappedValue)) 秒")
                            .foregroundStyle(Theme.muted)
                            .monospacedDigit()
                    }
                }
                .accessibilityLabel("时间线缓存时长")
            }
            Section("关于") {
                LabeledContent("版本", value: appVersion)
                NavigationLink { VersionsView() } label: { Text("工具链与设备基线") }
                Text(verbatim: "本项目为个人学习/开源演示，不上架、不商用、不批量抓取。")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var staleSeconds: Binding<Double> {
        Binding(
            get: { Double(Preferences.timelineStale(container.store)) / 1000 },
            set: { Preferences.setTimelineStale(Int($0 * 1000), store: container.store) })
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}

/// 版本基线页（PLAN §3「Xcode / Swift / 最低 iOS 版本记录到 `docs/VERSIONS.md`」的运行时对照）
struct VersionsView: View {
    var body: some View {
        List {
            LabeledContent("系统", value: ProcessInfo.processInfo.operatingSystemVersionString)
            LabeledContent("最低支持", value: "iOS 26（iPhone 11 / SE2 起）")
            LabeledContent("数据通道", value: "路线 B：离屏 WKWebView 双车道")
            LabeledContent("限流", value: "间隔 ≥1s · 并发 ≤2")
        }
        .navigationTitle("版本基线")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 他人主页（M5）

struct ProfileView: View {
    let uid: String
    @Environment(AppContainer.self) private var container
    @State private var user: WBUser?
    @State private var statuses: [WBStatus] = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if let user {
                    ProfileCard(user: user)
                }
                ForEach(statuses) { status in
                    StatusCell(status: status)
                        .padding(.horizontal, Theme.gutter - Theme.cardPadding)
                }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle(user?.screenName ?? "个人主页")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        let reader = WebReader(channel: container.channel)
        user = try? await reader.load(APIWebEndpoint.profileOverview, query: ["uid": uid], as: WBUser.self)
        let page = try? await container.timeline.loadPage(after: WebCursor.first)
        statuses = page?.items ?? []
    }
}

/// 资料卡：头像/简介/粉丝/关注数/微博数 + 关注按钮（M5 的乐观更新在此挂）
struct ProfileCard: View {
    let user: WBUser

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AvatarView(url: user.avatarURL, side: 60, verifiedType: user.verifiedType)
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.screenName).font(.title3.weight(.semibold))
                    if let reason = user.verifiedReason, !reason.isEmpty {
                        Text(reason).font(.caption).foregroundStyle(Theme.accent)
                    }
                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio).font(.footnote).foregroundStyle(Theme.muted).lineLimit(3)
                    }
                }
                Spacer()
                FollowButton(state: user.isFollowing)
            }
            HStack(spacing: 16) {
                Metric(value: user.statusCount, label: "微博")
                Metric(value: user.follows, label: "关注")
                Metric(value: user.followers, label: "粉丝")
            }
        }
        .padding(Theme.cardPadding)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Theme.gutter - Theme.cardPadding)
    }
}

private struct Metric: View {
    var value: Int
    var label: String

    var body: some View {
        HStack(spacing: 3) {
            Text(Self.format(value)).font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Theme.muted)
        }
    }

    static func format(_ value: Int) -> String {
        if value >= 10000 {
            return String(format: "%.1f万", Double(value) / 10000)
        }
        return String(value)
    }
}

/// 关注按钮：`nil` 表示"未知"，不渲染可点态（避免误显示"已关注"）
struct FollowButton: View {
    let state: Bool?

    var body: some View {
        switch state {
        case .some(true):
            Button("已关注") {}.buttonStyle(.glass)
        case .some(false):
            Button("关注") {}.buttonStyle(.glassProminent)
        case .none:
            EmptyView()
        }
    }
}
