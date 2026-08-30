import SwiftUI

// MARK: - 时间线首页（M2 的主战场；M0 只把"壳 + 数据链 + 状态四态"跑通）

struct TimelineHomeView: View {
    @Binding var path: [Route]
    @Environment(AppContainer.self) private var container
    @State private var model = TimelineModel()
    @State private var showLogin = false

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("首页")
                .navigationDestination(for: Route.self) { route in
                    RouteDestination(route: route)
                }
        }
        .refreshable { await model.load(provider: container.timeline) }
        .task {
            // 冷启动只探测一次会话；未登录直接进空态而不是弹登录页（R2）
            if !container.session.status.isLoggedIn, case .unknown = container.session.status {
                await container.session.probe(using: container.channel)
            }
            if container.session.status.isLoggedIn {
                await model.load(provider: container.timeline)
            }
        }
        .onChange(of: container.session.status) { _, next in
            // 登录态从外部（登录页 finish）转为已登录时，首页自动补一次加载
            if next.isLoggedIn, model.statuses.isEmpty {
                Task { await model.load(provider: container.timeline) }
            }
        }
        .sheet(isPresented: $showLogin) {
            LoginView()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .signedOut, .empty:
            SignedOutStateView { showLogin = true }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ErrorStateView(error: error) {
                Task { await model.load(provider: container.timeline) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading:
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(0 ..< 4, id: \.self) { _ in StatusSkeletonCell() }
                }
                .padding(.vertical, 8)
            }
        default:
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(model.statuses) { status in
                    StatusCell(status: status, onRoute: { path.append($0) })
                        .padding(.horizontal, Theme.gutter - Theme.cardPadding)
                        .contextMenu { statusMenu(status) }
                        .onTapGesture { path.append(.statusDetail(mid: status.id)) }
                }
                if model.canLoadMore {
                    MoreTrigger {
                        Task { await model.load(provider: container.timeline, more: true) }
                    }
                } else if !model.statuses.isEmpty {
                    Text("暂时没有更多了")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .padding(.vertical, 16)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
        .scrollIndicators(.hidden)
    }

    /// M4 的长按操作菜单（转发/评论/点赞/复制/收藏/分享）——先把结构立起来
    @ViewBuilder
    private func statusMenu(_ status: WBStatus) -> some View {
        Button("查看微博详情") { path.append(.statusDetail(mid: status.id)) }
        Button("复制正文") { UIPasteboard.general.string = HTMLText.strip(status.text) }
        Button("看作者") {
            if let uid = status.user?.id {
                path.append(.userProfile(uid: uid))
            }
        }
    }
}

/// 无限滚动触发器：进屏即请求下一页（游标推进见 `WebCursor.advancing`）
private struct MoreTrigger: View {
    var trigger: () -> Void
    @State private var fired = false

    var body: some View {
        Color.clear
            .frame(height: 1)
            .onAppear {
                guard !fired else { return }
                fired = true
                trigger()
            }
            .onDisappear { fired = false }
    }
}
