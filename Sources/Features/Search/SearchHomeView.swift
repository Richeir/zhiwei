import SwiftUI

// MARK: - 搜索与热搜（M6；M0 立 `.searchable` 语义 + 三 tab + 历史/防抖结构）

struct SearchHomeView: View {
    @Binding var path: [Route]
    @Environment(AppContainer.self) private var container

    @State private var query = ""
    @State private var submitted: String?
    @State private var tab: SearchTab = .status
    @State private var hotItems: [HotItem] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let submitted {
                    SearchResultsView(query: submitted, tab: tab)
                } else {
                    landing
                }
            }
            .navigationTitle("发现")
            .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索微博、用户、话题")
            .onSubmit(of: .search) { submit() }
            .task(id: debounceKey) { await loadHot() }
        }
    }

    /// 防抖：`.task(id:)` 天然带取消——输入变化即中止上一次请求（§M6「防抖请求、`.task(id:)` 竞态取消」）
    private var debounceKey: String {
        query
    }

    private var landing: some View {
        List {
            Section {
                Picker("范围", selection: $tab) {
                    ForEach(SearchTab.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            if !history.isEmpty {
                Section("搜索历史") {
                    ForEach(history, id: \.self) { item in
                        Button(item) {
                            query = item
                            submit()
                        }
                        .foregroundStyle(.primary)
                    }
                    Button("清空历史", role: .destructive) {
                        SearchHistoryStore(store: container.store).clear()
                        history = []
                    }
                }
            }
            Section("热搜") {
                if hotItems.isEmpty {
                    Text("暂无热搜数据（端点 \(APIWebEndpoint.hotSearch.key)）")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(hotItems) { item in
                        Button {
                            query = item.title
                            submit()
                        } label: {
                            HStack {
                                Text(verbatim: "\(item.rank)").font(.caption).foregroundStyle(Theme.muted)
                                    .frame(width: 22, alignment: .leading)
                                Text(item.title)
                                Spacer()
                                if let hot = item.hot {
                                    Text(Self.format(hot)).font(.caption).foregroundStyle(Theme.destructive)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    @State private var history: [String] = []

    private func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let store = SearchHistoryStore(store: container.store)
        store.record(trimmed, tab: tab)
        history = store.recent().map(\.query)
        submitted = trimmed
    }

    private func loadHot() async {
        try? await Task.sleep(for: .milliseconds(350)) // 防抖窗口
        guard !Task.isCancelled else { return }
        guard query.isEmpty, hotItems.isEmpty else { return }
        let reader = WebReader(channel: container.channel)
        hotItems = await (try? reader.load(APIWebEndpoint.hotSearch, as: HotSearchPayload.self))?
            .normalized() ?? []
        history = SearchHistoryStore(store: container.store).recent().map(\.query)
    }

    private static func format(_ value: Int) -> String {
        if value >= 10000 {
            return String(format: "%.1f万", Double(value) / 10000)
        }
        return String(value)
    }
}

/// 热搜条目（Web 侧边栏 `realtime` 数组的规整结果）
struct HotItem: Identifiable, Sendable, Equatable {
    var id: String {
        title
    }

    var rank: Int
    var title: String
    var hot: Int?
}

/// 热搜回包（内部结构两种口径：`realtime`（侧边栏）与 `list`）
struct HotSearchPayload: Decodable, Sendable {
    var realtime: [Entry]?
    var list: [Entry]?

    struct Entry: Decodable, Sendable {
        var note: String?
        var word: String?
        var title: String?
        var hotValue: LooseInt?

        enum CodingKeys: String, CodingKey {
            case note, word, title
            case hotValue = "hot_value"
        }

        var resolvedTitle: String? {
            title ?? word ?? note
        }
    }

    func normalized() -> [HotItem] {
        let entries = realtime ?? list ?? []
        return entries.enumerated().compactMap { index, entry in
            guard let title = entry.resolvedTitle else { return nil }
            return HotItem(rank: index + 1, title: title, hot: entry.hotValue?.value)
        }
    }
}

/// 搜索结果页（三 tab 共用，M6 补分页）
struct SearchResultsView: View {
    let query: String
    let tab: SearchTab

    var body: some View {
        EmptyStateView(
            symbol: "magnifyingglass",
            title: "搜索结果将在 M6 接通",
            message: "\(tab.rawValue)：\(query)")
            .navigationTitle("搜索结果")
            .navigationBarTitleDisplayMode(.inline)
    }
}
