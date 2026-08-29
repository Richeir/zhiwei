import SwiftUI

/// 设计令牌（PLAN §5 主题条目：`Color` 资源 + light/dark 跟随系统 + Liquid Glass 基础层定样）。
///
/// 原则：颜色一律来自 Assets（系统负责 light/dark 与增强对比度），代码里不出现十六进制；
/// 尺寸/间距集中在这里，避免各 Feature 自说自话。
enum Theme {
    // MARK: 颜色（Assets 定义，light/dark 由系统切换）

    /// 主强调色（关注态、链接、认证标识）
    static var accent: Color {
        Color("AccentColor")
    }

    /// 次要文字（来源、相对时间、计数）
    static var muted: Color {
        Color("MutedText")
    }

    /// 卡片底（非玻璃区域的常规表面）
    static var card: Color {
        Color("CardBackground")
    }

    /// 「降低透明度」下的玻璃回退底（无障碍模式不得出现透明穿帮，PLAN §5 / §9）
    static var glassFallback: Color {
        Color("GlassFallback")
    }

    /// 危险动作（取关、删除草稿）
    static var destructive: Color {
        Color(uiColor: .systemRed)
    }

    // MARK: 尺寸

    /// 页面左右留白
    static let gutter: CGFloat = 16
    /// 卡片内间距
    static let cardPadding: CGFloat = 12
    /// 头像默认边长（时间线 Cell）
    static let avatarSide: CGFloat = 44
    /// 九宫格单格最小边长
    static let gridMinTile: CGFloat = 96
    /// 玻璃件融合间距（`GlassEffectContainer` 的 spacing：越小越容易连成一片）
    static let glassSpacing: CGFloat = 12
    /// 正文行距（微博信息密度场景，比系统默认略紧）
    static let bodyLineSpacing: CGFloat = 4

    // MARK: 玻璃

    /// 统一的玻璃材质：浮层一律用它，保证融合与观感一致（D7：毛玻璃是系统语言而非自建效果）
    static var glass: Glass {
        .regular
    }

    /// 可交互件（按钮）在 `.regular` 上加互动响应
    static var interactiveGlass: Glass {
        .regular.interactive()
    }
}
