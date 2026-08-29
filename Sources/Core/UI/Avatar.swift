import SwiftUI

// MARK: - 共享组件层（PLAN §2.2「自建薄组件层（Cell/Avatar/RichText）」）

/// 头像：圆形 + 认证角标。微博头像地址是 CDN 静态资源，不需登录态。
struct AvatarView: View {
    var url: URL?
    var side: CGFloat = Theme.avatarSide
    /// 认证类型：`>= 0` 显示角标（-1 / nil 表示无认证）
    var verifiedType: Int?

    var body: some View {
        RemoteImageView(url: url, contentMode: .fill)
            .frame(width: side, height: side)
            .clipShape(Circle())
            .overlay(
                Circle().strokeBorder(Theme.muted.opacity(0.12), lineWidth: 0.5))
            .overlay(alignment: .bottomTrailing) {
                if let verifiedType, verifiedType >= 0 {
                    VerifiedBadge(verifiedType: verifiedType)
                        .offset(x: 1, y: 1)
                }
            }
            .accessibilityLabel("头像")
    }
}

/// 认证角标（蓝 V / 金 V / 灰 V）。用 SF Symbol 占位，正式素材待设计定稿。
struct VerifiedBadge: View {
    var verifiedType: Int

    private var color: Color {
        switch verifiedType {
        case 0: Theme.accent // 个人认证（金 V 在微博是橙，这里用强调色）
        case 1, 2, 3: Theme.accent.opacity(0.85) // 机构/企业/群控
        default: Theme.muted
        }
    }

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 11))
            .foregroundStyle(color)
            .background(Circle().fill(.background))
            .accessibilityLabel("已认证")
    }
}

/// 远程图片。
///
/// **通道边界的自我说明（PLAN §7 红线解释）**：限流 actor 管的是**微博业务 API**——那是风控的靶心。
/// `wx*.sinaimg.cn` 这类 CDN 静态资源不进 API 限流器，但也不是想发就发：
/// 1. 只允许 `sinaimg.cn` / `weibo.` 系域名（白名单在 `PictureHost`）；
/// 2. M2 的 Referer spike 决定是继续 `AsyncImage` 还是换 Kingfisher（自定义请求头）；
/// 3. 不做并发轰炸：调用方是懒加载列表，滚动才发请求。
struct RemoteImageView: View {
    var url: URL?
    var contentMode: ContentMode = .fit

    var body: some View {
        if let url, PictureHost.isAllowed(url) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty: placeholder
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: contentMode)
                case .failure:
                    // 图片失败不弹错误条（会淹没列表），只留灰底 + 极小图标
                    placeholder.overlay(Image(systemName: "photo").foregroundStyle(Theme.muted).font(.caption2))
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle().fill(Theme.muted.opacity(0.10))
    }
}

/// 允许加载的图片域（避免把通道变成任意 URL 代理）
enum PictureHost {
    static let allowedSuffixes = ["sinaimg.cn", "weibo.com", "weibo.cn", "sina.cn"]

    static func isAllowed(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        return allowedSuffixes.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}

/// 配图九宫格（M2：点击进入图片查看器，缩略图挂 `GlassID.photo` 做形变转场）
struct PictureGridView: View {
    let mid: String
    let pics: [WBPicture]
    var onTap: (Int) -> Void = { _ in }

    private var columns: [GridItem] {
        let count = pics.count == 1 ? 1 : min(3, pics.count)
        return Array(repeating: GridItem(.flexible(), spacing: 4), count: count)
    }

    var body: some View {
        if pics.isEmpty {
            EmptyView()
        } else if pics.count == 1 {
            // 单图限宽，避免一张长截图把整屏吃掉
            RemoteImageView(url: pics[0].url, contentMode: .fit)
                .frame(maxWidth: 240, maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture { onTap(0) }
        } else {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(pics.enumerated()), id: \.offset) { index, pic in
                    RemoteImageView(url: pic.url, contentMode: .fill)
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .onTapGesture { onTap(index) }
                        .accessibilityLabel("图片 \(index + 1)")
                }
            }
        }
    }
}
