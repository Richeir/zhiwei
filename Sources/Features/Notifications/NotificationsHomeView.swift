import SwiftUI

// MARK: - 消息中心（M7 P1；M0 只立三类通知的结构与未读角标位）

struct NotificationsHomeView: View {
    @Binding var path: [Route]
    @Environment(AppContainer.self) private var container

    @State private var kind: Kind = .mention

    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case mention = "@我"
        case comment = "评论"
        case repost = "转发"
        var id: String {
            rawValue
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker("类型", selection: $kind) {
                    ForEach(Kind.allCases) { item in Text(item.rawValue).tag(item) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 8)

                List {
                    Section {
                        EmptyStateView(
                            symbol: "bell",
                            title: "消息中心将在 M7 接通",
                            message: "端点已注册：\(APIWebEndpoint.notificationAt.key)")
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("消息")
            .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
            .refreshable { await refreshUnread() }
        }
    }

    /// 未读数轮询：只在 App 前台做（§M7「场景相位驱动」），频率刻意低
    private func refreshUnread() async {
        let reader = WebReader(channel: container.channel)
        _ = try? await reader.load(APIWebEndpoint.notificationAt, as: UnreadPayload.self)
    }

    private struct UnreadPayload: Decodable, Sendable {
        var unread: [String: LooseInt]?
    }
}
