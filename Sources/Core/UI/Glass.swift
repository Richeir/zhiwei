import SwiftUI

// MARK: - Liquid Glass 基础层（PLAN D7 / §5「Liquid Glass 基础层定样：玻璃浮层容器、
// `.buttonStyle(.glass)`、"降低透明度"无障碍模式下的回退观感」）
//
// 立场：**不重造毛玻璃**。iOS 26 起玻璃是系统语言，我们只负责三件事——
//   1. 把同类玻璃件放进同一个 `GlassEffectContainer`，让它们自动融合；
//   2. 给需要形变转场的件挂上 `glassEffectID`（M2 的"列表缩略图 → 全屏大图"用它）；
//   3. 在"降低透明度"下给出**不穿帮**的实色回退（§9 验收项）。

/// 玻璃浮层容器：包裹内容并纳入统一渲染组。
///
/// 内容自带 `.buttonStyle(.glass)` 时**不要**再叠加 `.glassEffect`，否则会看到两层玻璃。
struct GlassSurface<Content: View>: View {
    @Namespace private var namespace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let transitionID: String?
    private let spacing: CGFloat
    private let content: Content

    init(
        id transitionID: String? = nil,
        spacing: CGFloat = Theme.glassSpacing,
        @ViewBuilder content: () -> Content) {
        self.transitionID = transitionID
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if reduceTransparency {
            // 回退观感：实色胶囊 + 细描边，保持与玻璃件一致的圆角语言
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    Capsule()
                        .fill(Theme.glassFallback)
                        .overlay(Capsule().strokeBorder(Theme.muted.opacity(0.25), lineWidth: 0.5))
                }
        } else {
            GlassEffectContainer(spacing: spacing) {
                content
                    .glassEffectID(transitionID, in: namespace)
            }
        }
    }
}

/// 独立玻璃件（不属于任何按钮）：浮层底板、选中态强调等。
extension View {
    func zhiweiGlass(interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(ZhiweiGlassModifier(interactive: interactive, tint: tint))
    }
}

private struct ZhiweiGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var interactive: Bool
    var tint: Color?

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Theme.glassFallback, in: Capsule())
        } else {
            let base: Glass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
            content.glassEffect(interactive ? base.interactive() : base, in: Capsule())
        }
    }
}

/// 转场用的玻璃 ID 约定（M2：列表缩略图与全屏大图同名 ID，系统自动做形变过渡）
enum GlassID {
    static let compose = "compose"
    static func photo(mid: String, index: Int) -> String {
        "photo-\(mid)-\(index)"
    }
}
