import SwiftUI

// MARK: - 空态 / 错误态 / 骨架屏（PLAN §M2「骨架屏与空态/错误态」、§9「离线/弱网有明确降级 UI」）

/// 骨架 Cell：与 StatusCell 同布局，避免内容到达时跳动
struct StatusSkeletonCell: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle().fill(shimmer).frame(width: Theme.avatarSide, height: Theme.avatarSide)
                VStack(alignment: .leading, spacing: 6) {
                    bar(width: 120, height: 12)
                    bar(width: 80, height: 10)
                }
                Spacer()
            }
            bar(width: .infinity, height: 12)
            bar(width: .infinity, height: 12)
            bar(width: 200, height: 12)
            HStack(spacing: 28) {
                bar(width: 40, height: 10)
                bar(width: 40, height: 10)
                bar(width: 40, height: 10)
                Spacer()
            }
        }
        .padding(Theme.cardPadding)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
        .onAppear {
            // 「减少动态效果」模式下不起呼吸动画，只保留静态骨架（PLAN §5 无障碍回退）
            if !reduceMotion {
                pulsing = true
            }
        }
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(shimmer)
            .frame(maxWidth: width, minHeight: height, maxHeight: height)
    }

    /// 呼吸色：`Color` 本身就是 `ShapeStyle`，可直接作 `fill` 内容；动画由外层 `.animation(_:value:)` 统一驱动
    private var shimmer: Color {
        if reduceMotion {
            Theme.muted.opacity(0.12)
        } else {
            Theme.muted.opacity(pulsing ? 0.18 : 0.08)
        }
    }
}

/// 通用空态
struct EmptyStateView: View {
    var symbol: String = "tray"
    var title: String
    var message: String?
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(Theme.muted)
            Text(title).font(.headline)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle {
                Button(actionTitle, action: action).buttonStyle(.glass)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// 通用错误态：文案来自 `APIError.userMessage`，不裸露技术细节
struct ErrorStateView: View {
    let error: APIError
    var retry: () -> Void

    var body: some View {
        EmptyStateView(
            symbol: error == .notLoggedIn ? "person.crop.circle.badge.exclamationmark" : "wifi.exclamationmark",
            title: "这里没有内容",
            message: error.userMessage,
            actionTitle: error.isRetryable || error == .notLoggedIn ? "重试" : nil,
            action: retry)
    }
}

/// 未登录空态（M2 数据层要求：未登录要有明确空态而不是报错）
struct SignedOutStateView: View {
    var login: () -> Void
    var body: some View {
        EmptyStateView(
            symbol: "person.crop.circle.badge.questionmark",
            title: "还没有登录",
            message: "登录后即可刷微博。凭证只保存在系统 WebKit 里，App 不接触你的账号密码。",
            actionTitle: "去登录",
            action: login)
    }
}
