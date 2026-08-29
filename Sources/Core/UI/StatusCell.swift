import SwiftUI

// MARK: - 微博 Cell（PLAN §2.2 自建薄组件层 / M2「头像、昵称、认证标识、时间、来源、正文、配图九宫格」）
//
// M0 定结构与观感基线；转发嵌套的完整呈现、视频卡片、长文展开在 M2 补齐。
// 快照测试盯这个视图（§8.1「关键 View 的编译期构造 + snapshot-testing 视觉回归」）。

struct StatusCell: View {
    let status: WBStatus
    var onRoute: (Route) -> Void = { _ in }
    var onLike: (WBStatus) -> Void = { _ in }
    var onRepost: (WBStatus) -> Void = { _ in }
    var onComment: (WBStatus) -> Void = { _ in }

    /// 被转发的原文（转发微博时才有）
    private var subject: WBStatus {
        status.retweeted ?? status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            StatusTextView(html: subject.text, onRoute: onRoute)
            if let video = subject.video {
                VideoCard(video: video)
            }
            PictureGridView(mid: subject.id, pics: subject.pics) { index in
                onRoute(.photoViewer(urls: subject.pics.map(\.url), index: index))
            }
            if status.retweeted != nil {
                // 转发时把原文包一层浅底，视觉上和自己的正文分开
                repastedOriginal
            }
            actionBar
        }
        .padding(.vertical, 10)
        .padding(.horizontal, Theme.cardPadding)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: subject.user?.avatarURL, verifiedType: subject.user?.verifiedType)
                .onTapGesture {
                    if let uid = subject.user?.id {
                        onRoute(.userProfile(uid: uid))
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(subject.user?.screenName ?? "微博用户")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(WebDate.relative(subject.createdAt?.date, raw: subject.createdAt?.raw))
                    if let source = subject.source, !source.isEmpty {
                        Text("·")
                        Text(source.replacingOccurrences(of: "来自", with: ""))
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
    }

    private var repastedOriginal: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatusTextView(html: status.text, onRoute: onRoute) // 转发语
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.muted.opacity(0.08))
                .overlay(alignment: .leading) {
                    Text("@\(subject.user?.screenName ?? "微博用户")：\(HTMLText.strip(subject.text))")
                        .font(.footnote)
                        .lineLimit(3)
                        .padding(8)
                }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 28) {
            ActionItem(symbol: "arrow.2.squarepath", count: status.reposts, label: "转发") { onRepost(status) }
            ActionItem(symbol: "bubble.left", count: status.comments, label: "评论") { onComment(status) }
            ActionItem(symbol: "heart", count: status.attitudes, label: "点赞") { onLike(status) }
            Spacer()
        }
        .padding(.top, 2)
    }
}

private struct ActionItem: View {
    var symbol: String
    var count: Int
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(Self.format(count)).font(.footnote)
            }
            .foregroundStyle(Theme.muted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// "1.2万" 口径（与 Web 端一致，用户对数字的预期已经被训练好了）
    static func format(_ value: Int) -> String {
        if value >= 100_000_000 {
            return String(format: "%.1f亿", Double(value) / 100_000_000)
        }
        if value >= 10000 {
            return String(format: "%.1f万", Double(value) / 10000)
        }
        return value > 0 ? String(value) : ""
    }
}

/// 视频卡片（M2：内联预览 + 点击进入播放，播放用 `VideoView`（AVKit，iOS 26 原生））
struct VideoCard: View {
    let video: WBVideo

    var body: some View {
        ZStack {
            RemoteImageView(url: video.pageImageURL, contentMode: .fill)
                .aspectRatio(16 / 9, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Image(systemName: "play.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.9), .black.opacity(0.35))
        }
        .accessibilityLabel(video.title.map { "视频：\($0)" } ?? "视频")
    }
}
