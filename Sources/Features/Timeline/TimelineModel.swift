import Foundation
import os

// MARK: - 时间线状态（PLAN D6：`@Observable` + Repository；分页游标自研薄层）
//
// 设计取向：Model 不持有依赖，provider 由调用方传入。好处是 `@State private var model = TimelineModel()`
// 一行搞定，测试里直接塞 `WebTimelineProvider(channel: FakeWebViewChannel(...))`，不需要构造整个容器。

@MainActor
@Observable
final class TimelineModel {
    enum Phase: Sendable, Equatable {
        case idle
        case loading
        case refreshing
        case ready
        /// 回包正常但没有内容（且不会再有更多）
        case empty
        case signedOut
        case failed(APIError)
    }

    private(set) var phase: Phase = .idle
    private(set) var statuses: [WBStatus] = []
    private(set) var cursor = WebCursor.first
    private(set) var canLoadMore = true
    private var isLoadingMore = false

    var isEmpty: Bool {
        statuses.isEmpty
    }

    /// 拉取。`more == false` 表示刷新/首屏（重置游标）。
    func load(provider: any TimelineProviding, more: Bool = false) async {
        if more {
            guard canLoadMore, !isLoadingMore else { return }
            isLoadingMore = true
        } else {
            guard phase != .loading, phase != .refreshing else { return }
        }
        if !more {
            phase = statuses.isEmpty ? .loading : .refreshing
        }

        let target = more ? cursor : .first
        do {
            let page = try await provider.loadPage(after: target)
            // 去重：Web 端两页之间常有重叠条目，直接 append 会出现重复行
            let seen = Set(statuses.map(\.id))
            let fresh = page.items.filter { !$0.id.isEmpty && !seen.contains($0.id) }
            statuses += fresh
            cursor = cursor.advancing(with: page)
            canLoadMore = page.hasMore && !fresh.isEmpty
            phase = statuses.isEmpty ? (page.hasMore ? .ready : .empty) : .ready
        } catch let error as APIError {
            applyFailure(error)
        } catch {
            if statuses.isEmpty {
                phase = .failed(.transport(reason: String(describing: error)))
            }
        }
        if more {
            isLoadingMore = false
        }
    }

    /// 失败分诊：登录失效 → 引导空态；其余仅在无内容时清屏（R1：新鲜度让位于可用性）。
    private func applyFailure(_ error: APIError) {
        switch error {
        case .notLoggedIn:
            phase = .signedOut
        default:
            // 已有内容时不清屏：分页失败只影响"下一页"
            if statuses.isEmpty {
                phase = .failed(error)
            }
            if case .rateLimited = error {
                canLoadMore = false
            }
            Logger.log(domain: .timeline).error("load failed: \(String(describing: error), privacy: .public)")
        }
    }
}
