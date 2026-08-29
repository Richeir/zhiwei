import SwiftUI

// MARK: - 微博详情（M4 主战场；M0 立结构与四态）

struct DetailView: View {
    enum Focus: Equatable, Sendable {
        case main
        case comments(maxID: String?)
        case reposts
    }

    let mid: String
    var focus: Focus = .main

    @Environment(AppContainer.self) private var container
    @Environment(\.appNavigator) private var navigator

    @State private var status: WBStatus?
    @State private var error: APIError?
    @State private var loading = true

    var body: some View {
        Group {
            if let status {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        StatusCell(status: status, onRoute: { route in
                            navigator.go(.to(route))
                        })
                        // 评论列表在 M4：分页 + 发评论 + 楼中楼
                        SectionHeader("评论")
                        EmptyStateView(
                            symbol: "bubble.left",
                            title: "评论列表将在 M4 接通",
                            message: "端点已注册：\(APIWebEndpoint.commentsList.key)")
                    }
                    .padding(.vertical, 8)
                }
            } else if let error {
                ErrorStateView(error: error) { Task { await load() } }
            } else if loading {
                StatusSkeletonCell().padding()
            }
        }
        .navigationTitle("微博详情")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let reader = WebReader(channel: container.channel)
            status = try await reader.load(APIWebEndpoint.statusShow, query: ["id": mid], as: WBStatus.self)
        } catch let apiError as APIError {
            error = apiError
        } catch {
            // `catch` 隐式绑定的 `error` 遮蔽了 @State 属性，必须显式走 self
            self.error = .transport(reason: String(describing: error))
        }
    }
}

/// 区块标题（各 Feature 共用，避免每个页面自造一套字号）
struct SectionHeader: View {
    let title: String
    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 4)
    }
}
