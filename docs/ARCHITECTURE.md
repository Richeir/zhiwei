# ARCHITECTURE —— 架构与技术决策记录（D1–D9）

> 本文件是 PLAN.md §5 的出口条件交付物：**记录 D1–D9 决策与理由（含废弃项说明）**。
> 所有结论以 [`PLAN.md`](../PLAN.md) 为准；本文只做整理转述与边界说明，不新增决策，两者冲突时以 PLAN.md 为准。
> 编号约定：**废弃编号不重排**（D2/D3、R3–R5、M8），以保持交叉引用稳定（PLAN §3 注、AGENTS.md 约定）。

---

## 1. 项目定位与硬约束

### 1.1 定位（PLAN §1、§1.1 / R1 前提）

| 项 | 内容 |
|---|---|
| 产品形态 | 新浪微博第三方客户端，**仅 iOS 单平台**，不为多端预留任何设计约束 |
| 技术栈 | Swift + SwiftUI；WKWebView 仅作登录与数据通道宿主；依赖走 SPM |
| 平台底线 | 最低 **iOS 26**（iPhone 11/SE2 起；XR/XS 止步 iOS 18，个人演示定位无碍）；Xcode 26 / Swift 6.2 |
| 数据来源 | **微博 Web 端接口**（无需开放平台申请；路线 B 见 D9；合规前提见 R1） |
| 用途与分发 | 个人学习 / 开源演示，仅 GitHub 分发；**不上架、不商用、不批量抓取** |
| 执行方式 | AI 全量执行（编码、测试脚手架、CI）；人负责验收走查、真机操作与风控人工验证。§10 提示：**验收排队可能取代编码成为瓶颈**，DoD 应设计为可批量验收 |

### 1.2 硬约束（任何改动不得突破）

| # | 硬约束 | 出处 |
|---|---|---|
| C1 | 工程由 XcodeGen `project.yml` 文本定义；`*.xcodeproj` 是生成产物，禁止入库、禁止手改 pbxproj | D4、AGENTS.md、§5 |
| C2 | 微博 Web 端点定义全部收敛 `Core/APIWeb/`，Web 改版**只动这一处** | D9、R1 缓解④ |
| C3 | 所有网络入口收敛 `WebViewChannel` 协议，任何库/请求不得绕行限流 actor（间隔 ≥1s、并发 ≤2） | §7、AGENTS.md |
| C4 | 登录凭证仅存系统 WebKit CookieJar，不落 App 自有存储与日志 | D9、R2、§9 |

### 1.3 风险与护栏映射（PLAN §3，保留原编号）

| 风险 | 等级 | 护栏（缓解措施） |
|---|---|---|
| **R1** Web 接口属未授权通道：违反用户协议（禁止自动化未授权访问）；432 限频、滑块、字段变更是常态（[weibo-crawler 432 实例](https://github.com/dataabc/weibo-crawler/issues/565)） | 高（合规）/ 中（工程） | ① 三不定位；② 全局限流 actor + 缓存，**新鲜度让位于低调**；③ 触发风控唤起可见 WebView 人工验证后自动重放；④ 端点收敛 APIWeb；⑤ README 显著免责声明 |
| **R2** Web 会话维护：扫码登录、Cookie 过期、多端互踢 | 中 | 登录在嵌入式 WKWebView 人工完成，App 不碰账密/加密参数；命中 401/跳登录页即自动唤起重新登录；会话持久化依赖 `WKWebsiteDataStore.default()`，模拟器与真机分别实测 |
| **R6** 长列表 + 富文本 + 图片在老款 iPhone 上的 SwiftUI 回收/解码抖动未经检验 | 低–中 | M2 结束前 1k 条时间线滚动压测（Instruments + 真机帧率）；性能出口：真机 ≥ 50fps、冷启动 < 2s（§9） |
| **R7** 路线 B 四个待证点（见 §4.4） | 中（原 RN 时代为高：①②是原生成熟技巧，③④相比 JS 桥是确定性提升） | M0 首个 spike **四项判据全过**才算通过；任一失败按 §4.4 预案处置，M0 收尾定案，**不带病进入 M1** |

> 废弃风险编号 R3–R5 见 §3.10。

---

## 2. 分层与目录职责（PLAN §2.2）

分层原则：`App` 组装 → `Features/*` 按功能域垂直切分 → `Core/*` 提供通道与横切能力；服务端数据统一经 Repository（D6）走 `APIWeb` 端点定义，最终收敛到 `WebViewChannel`（C3）。**Features 之间不互相依赖数据通道，一律经 Core。**

| 路径 | 职责 | 变更纪律 / 备注 |
|---|---|---|
| `project.yml` | XcodeGen 工程定义；**SPM 版本约束声明于此**（生成的 xcodeproj 不入库，其内 `Package.resolved` 随之失效，约束必须落文本定义） | C1 |
| `Sources/App/` | `@main`、TabView 壳、集中式导航 Route enum、Theme、DI 组装根 | D5、§5 |
| `Sources/Features/Auth/` | 登录（WKWebView 扫码 sheet）、会话检测、登出 | M1 |
| `Sources/Features/Timeline/` | 关注/推荐时间线 | M2 |
| `Sources/Features/Compose/` | 发布微博（文字/图片/话题） | M3，走车道② |
| `Sources/Features/Detail/` | 详情、评论、转发、点赞 | M4 |
| `Sources/Features/Profile/` | 用户主页、关注列表 | M5 |
| `Sources/Features/Search/` | 搜索、热搜 | M6 |
| `Sources/Features/Notifications/` | 消息中心 | M7（P1） |
| `Sources/Core/WebViewChannel/` | 离屏 WKWebView 宿主、双车道、**限流 actor**、风控降级 | 唯一网络入口（C3）；M0 定样 + spike 验证，生产实现归 M1（§5 边界） |
| `Sources/Core/APIWeb/` | Web 端点注册表、DTO（`Codable`）、分页游标；`web/` 默认实现、`openapi/` 留位 | 端点全部收敛于此（C2） |
| `Sources/Core/Store/` | 偏好/草稿/搜索历史 KV | **凭证永不落此**（C4） |
| `Sources/Core/UI/` | 共享薄组件（Cell/Avatar/RichText）+ Liquid Glass 视觉层 | D7 |
| `Sources/Resources/` | Assets.xcassets / Localizable | `Color` 资源 + light/dark 跟随系统（§5） |
| `Tests/` | XCTest 单元 + 契约快照 | 以 `WebViewChannel` 协议为注入边界做 fake（回放契约 JSON），UI 测试不依赖真微博（§8.1） |
| `Scripts/`、`docs/` | 脚本与文档 | `docs/ARCHITECTURE.md`（本文件）与 `docs/VERSIONS.md`（版本基线，M0 已建） |

---

## 3. 决策记录（D1–D9，四段式）

### D1 · UI 栈
- **决策**：SwiftUI-first，UIKit **定点桥接**：列表/导航/表单全 SwiftUI；WKWebView 宿主、个别交互（图片查看器手势）经 `UIViewRepresentable` 下沉 UIKit，不追求纯血。
- **理由**：iOS 26 底零兼容包袱——Swift 6.2 严格并发、`@Observable`/`NavigationStack`/Liquid Glass 全量可用；毛玻璃、原生转场、系统级导航是本栈第一梯队资产，尽情用（PLAN 卷首）。
- **备选与否决原因**：纯血 SwiftUI（为个别手势硬扛 SwiftUI 能力缺口）与 UIKit 全面铺开均未采纳——PLAN 明言"不追求纯血"；RN/JS 栈整体随 D8 废弃，完整论证在 git 历史。
- **影响面**：`Features/*` 全部页面为 SwiftUI；WKWebView 桥接代码收敛 `Core/WebViewChannel`；图片查看器是 M2 的定点 UIKit 场景。

### D2 · 桌面端框架（已废弃）
- **决策**：—（已废弃）。
- **理由**：原选择 react-native-macos 作桌面端框架；技术栈转 Swift（D8）后，连同"多平台"前提一并废弃。
- **备选与否决原因**：不适用——本条整体废弃，非改选。
- **影响面**：无代码影响；**编号保留不重排**，以稳定 M9 与 §10 的引用链（见 §3.10）。

### D3 · 多平台组织（已废弃）
- **决策**：—（已废弃）。
- **理由**：原设计为平台扩展文件支撑多平台组织；单平台单栈（iOS only，§1.1）下不存在跨端分叉，前提消失。
- **备选与否决原因**：不适用——随"多平台"目标整体废弃。
- **影响面**：仓库结构中不设任何跨端目录；**编号保留不重排**（见 §3.10）。

### D4 · 工程管理
- **决策**：**XcodeGen（`project.yml` 文本定义）+ SPM 依赖**。
- **理由**：工程文件不手改 pbxproj，AI 可全量生成与 review；依赖走 SPM，**无 CocoaPods**。
- **备选与否决原因**：手维护 pbxproj（AI/人都难以可靠 review，diff 噪音大）与 CocoaPods（明确排除）被否决。
- **影响面**：C1 全链路——`.gitignore` 排除生成的 xcodeproj；CI 流程固定为 `xcodegen generate` → `xcodebuild`（§8.2）；SPM 版本约束必须写在 `project.yml`；README"clone → xcodegen → 运行"三步（§8.3）。

### D5 · 导航
- **决策**：SwiftUI `NavigationStack` + `TabView`，Route 定义为 **enum**（集中式）。
- **理由**：系统原生栈免费获得大标题、滑动返回、contextMenu、`.searchable`。
- **备选与否决原因**：自建路由/第三方导航库未采纳——系统能力已覆盖（§7 准入三问第一问即否定此类引入）。
- **影响面**：`Sources/App/` 持有 TabView 壳与 Route enum（§5）；各 tab 内独立 NavigationStack；M6 搜索直接吃 `.searchable` 红利。

### D6 · 状态与数据
- **决策**：**Observation（`@Observable`）+ URLSession + Repository 层**；分页/缓存/游标自研薄层；服务端数据统一走 `APIWeb` Repository。
- **理由**：Apple 官方观察框架，**不引入大型三方状态库**。
- **备选与否决原因**：大型三方状态库（Redux/MVI 类）被否决：违背"能少则少，系统优先"（§7），且 Observation 已够。
- **影响面**：M1 的 `UserSession` 用 `@Observable`；Repository 层承担 staleTime + 磁盘缓存（M2），并落实"**降低风控触发概率优先于数据新鲜度**"（R1 缓解②）；限流 actor 属通道层而非状态层（C3）。

### D7 · UI 组件
- **决策**：自建薄组件层（Cell/Avatar/RichText）+ **Liquid Glass 视觉层**：`.glassEffect` + `GlassEffectContainer`（相邻玻璃自动融合）、`.buttonStyle(.glass)`、`glassEffectID` 形变转场；toolbar/tab bar 系统默认即玻璃。
- **理由**：毛玻璃是**系统语言而非自建效果**；微博信息密度场景组件有限，自建成本低于选型内耗；视觉红利是换 Swift 的直接动机之一。
- **备选与否决原因**：第三方 SwiftUI 组件库选型被否决（"自建成本低于选型内耗"）。
- **影响面**：`Core/UI` 承载共享组件与玻璃层；§5 要求玻璃浮层、`.buttonStyle(.glass)` 及**"降低透明度"无障碍模式回退观感**定样；M2 落地发博按钮/图片形变转场与各滚动边缘行为走查；§9 验收 light/dark + 降低透明度渲染正确。

### D8 · 语言
- **决策**：**Swift 全覆盖**。
- **理由**：随技术栈由 RN 切换至原生 Swift/SwiftUI；原语言为 TypeScript。
- **备选与否决原因**：TypeScript/RN 栈被整体废弃（其通道与架构风险一并退场，见 §3.10 R3–R5 注）；RN 时代的完整技术论证与代码记录**保留在 git 历史**，不在当前仓库结构里留残影。
- **影响面**：全仓库单一语言；§8.2 CI 为 SwiftLint/SwiftFormat/xcodebuild 工具链。

### D9 · 数据通道（路线 B，原生化）
- **决策**：常驻**离屏 WKWebView** 保持已登录的 weibo.com 同源会话；**双车道**取数——车道①页面内 fetch（`evaluateJavaScript` 注入 + `WKScriptMessageHandlerWithReply` 结构化回传）用于业务读接口；车道②原生 URLSession（经 `WKHTTPCookieStore` 同步 Cookie）主要用于**上传/发布**，亦用于不依赖页面上下文的轻量直发（如会话探测）。`Core/APIWeb` 保留后端抽象（`web/` 默认实现，`openapi/` 留位）。展开见 §4。
- **理由**：免申请、免审核；相比 RN 路线两大质变——**(a)** `WKHTTPCookieStore.getAllCookies` 原生可直接读 **httpOnly** 的 `SUB`/`XSRF-TOKEN`，不再依赖"页面脚本能读到"这个未证假设；**(b)** CORS 只是浏览器安全模型，**URLSession 上传天然不受限**，只需按服务端校验补齐 Referer/Origin 头。
- **备选与否决原因**：开放平台 API（路线 A）需申请、有审核与权限限制，仅作备用通道留位（`openapi/`，参考 §11 文档）；RN 桥接 WebView 方案因 (a)(b) 两点在原生语境下从"赌未证假设"变为"成熟技巧 + 待实测"而弃。
- **影响面**：代价不变 = **风控长期维护（R1）+ WebView 常驻内存**；C2/C3/C4 三条硬约束全部由本决策派生；M1 的一切（登录、会话、Cookie 同步）建立其上。

### 3.10 废弃编号说明（为何保留、为何不重排）

| 编号 | 原内容 | 废弃原因 |
|---|---|---|
| D2 | 桌面端框架（react-native-macos） | 技术栈转 Swift，随"多平台"前提一并废弃 |
| D3 | 多平台组织（平台扩展文件） | 单平台单栈，不存在跨端分叉 |
| R3 | RN ↔ RN macOS 版本对齐 | 随 macOS 平台移除 |
| R4 | 三方库跨端覆盖 | 收缩进 §7 依赖清单（单平台语境） |
| R5 | Windows 平台相关风险 | 随 Windows 平台移除 |
| M8 | 桌面端专项打磨（macOS） | 随平台与技术栈移除而废弃 |

**编号有意不回排**：D1–D9、R6/R7、M9 在 PLAN §3/§6/§10、AGENTS.md 及历史提交信息中被交叉引用；重排会使所有既有引用静默错位。修订约定（AGENTS.md）：废弃即标注、编号不动，改动需同步相关 DoD 与风险判据，并以 `docs: 计划修订 vX——摘要` 形式提交。RN 整体时代的通道与架构风险随 D8 的技术栈切换一并退场，其完整论证见 git 历史。

---

## 4. 数据通道：路线 B 双车道（D9 展开）

### 4.1 通道形态与生命周期

- 宿主：**常驻离屏 WKWebView**，保持 weibo.com 同源会话（weibo.com 源常驻）。
- 登录：sheet 内嵌**可见** WKWebView 打开微博**扫码登录页**，用户人工完成（含滑块/短信），App 全程不接触账密/加密参数（R2）。
- 会话检测：轻量端点探测登录态——走**车道②原生直发**（带 Cookie）；过期/命中 401/跳登录页 → 自动唤起重新登录（M1）。
- 登出：登出 + `WKWebsiteDataStore.default().removeAllData()`（M1）；重启会话恢复依赖系统 CookieJar 持久化，模拟器 + 真机实测。

### 4.2 双车道对比

| | 车道① 页面内 fetch | 车道② 原生 URLSession |
|---|---|---|
| 机制 | `evaluateJavaScript` 在页面上下文注入 fetch，结果经 `WKScriptMessageHandlerWithReply` **结构化回传**，请求 ID ↔ 回包关联 | 原生请求；Cookie 由 `WKHTTPCookieStore` 读取（**含 httpOnly 的 `SUB`/`XSRF-TOKEN`**）→ 注入 `HTTPCookieStorage.shared` 自动携带 |
| 主用途 | 业务读接口（时间线、详情、评论、搜索等） | **上传/发布**（multipart + 按服务端校验补 Referer/Origin 头）；亦用于不依赖页面上下文的轻量直发（会话探测） |
| 优势 | 天然同源、页面上下文齐备 | 不受 CORS 约束（浏览器安全模型与原生无关）；httpOnly Cookie 原生直读——相比 RN 路线的质变点 (a)(b) |
| 待证 | R7 判据①② | R7 判据③④ |

两条车道都从 `WebViewChannel` 协议进出，共用同一个限流 actor（C3）。

### 4.3 协议与错误模型（M0 定样）

- 接口定样：`WebViewChannel { func fetch(_:) async throws -> Data }`；`APIError` enum 含 **`.punished`** case（风控识别的显式表达）。
- §5 边界：通道类条目在 M0 **只定样并用 spike 级实现（可抛弃代码）验证 R7 判据**；生产实现（含限流 actor：间隔 ≥1s、并发 ≤2、超时/重试）归 M1。
- 测试注入边界：该协议即 §8.1 fake 的边界（回放 Web 端点契约 JSON），UI 测试不依赖真微博；契约快照测试使"微博改字段第一时间发现"（§7 swift-snapshot-testing）。

### 4.4 R7 四项判据与失败预案（M0 spike 全过才放行）

| # | 待证点 | 已知解法 / 预期 | 失败处置 |
|---|---|---|---|
| ① | 离屏/隐藏 WKWebView 是否被系统挂起 | 原生已知解法：入屏 1×1 视图或独立 UIWindow，需实测 | **①②任一失败 → 常驻可见层级小窗** |
| ② | 页面内 fetch 经消息桥回传，在 App 前后台切换/锁屏恢复后的存活 | 需实测；M1 要求隐藏态/前后台/锁屏恢复存活实测通过 | 同上 |
| ③ | `WKHTTPCookieStore` 读到含 httpOnly 的 `SUB`/`XSRF-TOKEN` 并成功附带 | 原生直读，RN 时代的未证假设已成确定性提升 | **失败 → 回车道①**（页面内取数含附带） |
| ④ | 原生 URLSession 直传上传域名时服务端的 Referer/Origin/参数校验行为 | 按服务端校验补头，需实测（M3 以实测为准） | **失败 → 上传/发布改走可见 WKWebView 内完成** |

### 4.5 风控降级链路（方案 M0 定样，实现归 M1）

识别 punish/验证码响应（`APIError.punished`）→ 唤起**可见** WKWebView 让用户**人工验证** → 自动重放失败请求。与 R1 缓解③一致：降级靠人工过验证恢复，**不做任何绕过风控的尝试**。

### 4.6 端点定义落位

weibo.com ajax 为主、m.weibo.cn container 兜底（M2）；端点名与分页游标参数**以实测为准**，全部收敛 `Core/APIWeb/`（C2）——Web 改版的唯一变更点。

---

## 5. 合规红线（R1）

1. **三不**：不上架任何应用商店、不商用（含付费分发）、不批量抓取/存库/数据分析；仅个人学习/开源演示，GitHub 分发（§1.1、README 免责声明）。
2. **限流不可协商**：全局限流 **间隔 ≥1s、并发 ≤2**，以 actor 实现（超时/重试、退避/去重由单测覆盖）；配合 Repository 缓存，**新鲜度让位于低调**。
3. **入口唯一**：所有网络入口收敛 `WebViewChannel` 协议，**任何库（含 Kingfisher/Sentry 等三方）不得绕行限流器直接发请求**（§7、C3）。新增依赖若自带独立网络路径，必须先回答"能否被协议注入替代"。
4. **抓取姿态**：不导出、不批量保存数据（README"已知限制"）；保持个人账号低频使用。
5. **分发**：仅限 Apple 签名体系内本机自签（免费账号 7 天重签；日常主力机建议付费账号）；**不用 TestFlight**——外部测试组需过 App Store Connect Beta 审核，与"不上架"及 R1 低调姿态冲突（§8.3）。
6. **文案义务**：README 显著位置放免责声明（与服务器友好、风险自负、随时失效是正常预期）与已知限制清单（§9）。

## 6. 凭证红线（C4 / R2）

| 规则 | 落地 |
|---|---|
| 凭证唯一栖身地 = 系统 WebKit CookieJar（`WKWebsiteDataStore.default()`） | 会话持久化、重启恢复均依赖它；登出即 `removeAllData()` |
| **App 自有存储不落凭证** | `Core/Store` 只存偏好/草稿/搜索历史 KV（§5）；Keychain 亦不需要（§7 KeychainAccess 条） |
| **日志不得出现凭证** | `os.Logger` 按子系统分域；Sentry 仅占位且遵守本红线（§5、§7） |
| App 不接触账密 | 登录全程人工在 WKWebView 内完成，App 不碰账密/加密参数（R2） |
| 验收口径 | §9：App 自有存储与日志中**无任何 Cookie/凭证** |

---

## 7. 依赖准入与当前清单（PLAN §7：能少则少，系统优先）

**准入三问**（新库必须先过，按需追加到清单）：

1. 系统能力是否覆盖？
2. 是否可被 20 行薄封装替代？
3. 维护活跃度与 SPM 支持如何？

| 库 | 用途 | 当前结论 |
|---|---|---|
| WKWebView / URLSession / AVKit | 通道、网络、播放（`VideoView` iOS 26 SwiftUI 原生） | 系统自带，零依赖 |
| PhotosPicker | 图片选择 | 系统能力，免相册权限读图（M3） |
| Kingfisher | 图片加载 + 缓存 + 自定义请求头 | **待定**：M2 spike 与 `wx*.sinaimg.cn` Referer 实测一起定；失败退 `URLSession` 手写缓存 |
| swift-snapshot-testing | 端点契约快照 + 关键视图快照 | 引入：微博改字段第一时间发现 |
| Sentry Cocoa SDK | 崩溃与日志上报 | **目前仅占位**；遵守"日志不含凭证"红线（§6） |
| KeychainAccess（或原生 Security） | — | **基本不需要**：路线 B 下凭证留在 WebKit CookieJar；仅存其他敏感信息时再引 |
| swiftlint / swiftformat | 静态检查与格式化，接入 pre-commit 与 CI 门禁 | 工具链，不进包体 |

版本约束声明在 `project.yml`（D4）；网络类库受 §5 第 3 条入口唯一约束。

---

## 8. 已知未定项（均须按 PLAN 节点收敛，不得悬置）

| # | 未定项 | 定案时点 / 依据 |
|---|---|---|
| U1 | R7 四判据实测结论（§4.4） | **M0 收尾必须定案，不带病进 M1**（§10） |
| U2 | Kingfisher 是否引入 | M2 图片 spike + Referer 实测一起定；退路已列（§7） |
| U3 | 各业务端点的实际 URL 与分页游标参数（weibo.com ajax / m.weibo.cn container） | 以实测为准并全部收敛 `Core/APIWeb/`（C2） |
| U4 | 车道②上传的 Referer/Origin/参数具体校验行为 | R7 判据④；失败预案 = 发布走可见 WKWebView（M3） |
| U5 | `openapi/` 留位的最终形态 | 仅作后端抽象占位（D9）；路线 B 失效时依 §11 开放平台文档重新论证 |
| U6 | 收藏能力 | 若 API 可得，否则记 P2（M4） |
| U7 | 私信 | 首版降级"跳网页版"，P2 再评估（M7） |
| U8 | 正式开源协议 | 未定稿；README 声明将采用含**非商业条款**的协议，与 R1 一致 |
| U9 | 签名账号形态（免费 7 天重签 vs 付费 ≥1 年） | 按使用强度定（§8.3）；分发渠道本身不变（不上架、不用 TestFlight） |
| U10 | `docs/VERSIONS.md` | **已定案（M0）**：Xcode / Swift / 最低 iOS 版本已落入 `docs/VERSIONS.md`；工具链或设备变化时同步更新 |

---

*变更记录：本文件随 PLAN.md 修订同步；废弃编号不重排；提交信息遵循 `docs: 计划修订 vX——摘要`（AGENTS.md）。*
