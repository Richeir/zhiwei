import SwiftUI

// MARK: - 路由 → 目的视图（PLAN D5：Route enum 集中，系统导航栈负责转场与返回手势）

struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .statusDetail(let mid):
            DetailView(mid: mid)
        case .comments(let mid, let maxID):
            DetailView(mid: mid, focus: .comments(maxID: maxID))
        case .reposts(let mid):
            DetailView(mid: mid, focus: .reposts)
        case .userProfile(let uid):
            ProfileView(uid: uid)
        case .topic(let name):
            SearchResultsView(query: "#\(name)#", tab: .status)
        case .photoViewer(let urls, let index):
            PhotoViewerView(urls: urls, startIndex: index)
        case .searchResults(let query, let tab):
            SearchResultsView(query: query, tab: tab)
        case .web(let url):
            // 兜底承载：Web 接口拿不到等价原生结构时用；M0 不放行第三方链接（R1 低调）
            ExternalUnsupportedView(url: url)
        }
    }
}

/// 大图查看器（M2：`matchedGeometryEffect` / `glassEffectID` 列表→详情转场、缩放翻页）
struct PhotoViewerView: View {
    let urls: [URL]
    @State private var index: Int
    @Environment(\.dismiss) private var dismiss

    init(urls: [URL], startIndex: Int) {
        self.urls = urls
        _index = State(initialValue: min(max(startIndex, 0), max(urls.count - 1, 0)))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(urls.enumerated()), id: \.offset) { position, url in
                    ZoomableImageView(url: url)
                        .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(12)
                }
                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .accessibilityLabel("图片 \(index + 1)/\(urls.count)")
    }
}

/// 双指缩放（UIKit 手势下沉位，PLAN D1：个别交互经 `UIViewRepresentable` 桥接）
struct ZoomableImageView: View {
    let url: URL

    var body: some View {
        // M2 实装：UIScrollView 承载 + 自定义请求头（与 Referer spike 一起定）
        RemoteImageView(url: url, contentMode: .fit)
            .padding()
    }
}

/// 不支持在 App 内打开的链接：给出明确去向，而不是静默失败（§9 降级 UI）
struct ExternalUnsupportedView: View {
    let url: URL

    var body: some View {
        EmptyStateView(
            symbol: "arrow.up.forward.app",
            title: "这个内容暂不支持在 App 内查看",
            message: url.host ?? "",
            actionTitle: "在浏览器中打开",
            action: { UIApplication.shared.open(url) })
            .navigationTitle("提示")
    }
}
