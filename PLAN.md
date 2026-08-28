# 新浪微博客户端（iOS · Swift + SwiftUI）项目计划

> 目标：用 **Swift + SwiftUI** 构建一个微博客户端，**仅 iOS 单平台**，不为多端预留任何设计约束。
> 毛玻璃（Material）、原生转场、系统级导航这些平台能力是本栈的第一梯队资产，尽情用。
>
> 交付物约定：每个里程碑（Mx）都有验收标准（DoD）与可勾选的任务清单。

---

## 1. 项目概述

| 项 | 内容 |
|---|---|
| 产品形态 | 新浪微博第三方客户端（iOS） |
| 技术栈 | Swift + SwiftUI（WKWebView 仅作登录与数据通道宿主）+ Swift Package Manager |
| 平台 | iOS（最低支持 **iOS 17**，用 `@Observable`/NavigationStack；装旧设备则降 16 换 `ObservableObject`，M0 定） |
| 数据来源 | **微博 Web 端接口**（无需开放平台申请；路线 B：隐藏 WKWebView 同源会话，见 D9；合规约束见 R1） |
| 执行方式 | **AI 全量执行**（编码、测试脚手架、CI 配置）；人负责验收走查、真机操作与风控人工验证环节 |

### 1.1 产品目标（P0 = 首版必须，P1 = 首版尽量，P2 = 后续迭代）

- [ ] 项目定位：**个人学习 / 开源演示**，仅 GitHub 分发，不上架商店、不商用、不批量抓取（路线 B 的合规前提，见 R1）
- [ ] P0 能登录、看时间线、刷微博、发微博
- [ ] P0 微博详情：正文、图片/视频、评论、转发、点赞
- [ ] P0 个人主页：用户资料、微博列表、关注/取关
- [ ] P1 搜索（微博/用户/话题）与热搜榜
- [ ] P1 消息中心（@我、评论、转发通知）
- [ ] P1 SwiftUI 原生体验：毛玻璃导航栏/浮层（Material）、大图缩放转场、Dynamic Type
- [ ] P2 私信、长文、视频直播、小组件（WidgetKit 顺手可做）等

---

## 2. 技术方案总览

### 2.1 关键决策

| # | 决策点 | 选择 | 理由 / 备选 |
|---|---|---|---|
| D1 | UI 栈 | **SwiftUI-first，UIKit 定点桥接** | 列表/导航/表单全 SwiftUI；WKWebView 宿主、个别交互（图片查看器手势）经 `UIViewRepresentable` 下沉 UIKit，不追求纯血 |
| D2 | 桌面端框架 | —（已废弃） | 原 react-native-macos；技术栈转 Swift 后连同"多平台"前提一并废弃 |
| D3 | 多平台组织 | —（已废弃） | 原平台扩展文件；单平台单栈，不存在跨端分叉 |
| D4 | 工程管理 | **XcodeGen（`project.yml` 文本定义）+ SPM 依赖** | 工程文件不手改 pbxproj，AI 可全量生成与 review；依赖走 SPM，无 CocoaPods |
| D5 | 导航 | **SwiftUI `NavigationStack` + `TabView`**，Route 定义为 enum | 系统原生栈：大标题、滑动返回、contextMenu、`.searchable` 全部免费 |
| D6 | 状态与数据 | **Observation（`@Observable`）+ URLSession + Repository 层**（分页/缓存/游标自研薄层） | Apple 官方观察框架，不引入大型三方状态库；服务端数据统一走 `APIWeb` Repository |
| D7 | UI 组件 | 自建薄组件层（Cell/Avatar/RichText）+ **Material 视觉层**（`.ultraThinMaterial` 毛玻璃导航栏、浮层、`.toolbarBackground`） | 微博信息密度场景组件有限，自建成本低于选型内耗；视觉红利是换 Swift 的直接动机之一 |
| D8 | 语言 | **Swift** 全覆盖 | 原 TypeScript；RN 时代的完整技术论证与代码记录在 git 历史 |
| D9 | **数据通道（路线 B，原生化）** | 常驻**离屏 WKWebView** 保持已登录的 weibo.com 同源会话；双车道取数：**车道① 页面内 fetch**（`evaluateJavaScript` 注入，`WKScriptMessageHandlerWithReply` 结构化回传）用于业务读接口；**车道② 原生 URLSession**（经 `WKHTTPCookieStore` 同步 Cookie）用于**上传/发布**。`Core/APIWeb` 保留后端抽象（`web/` 默认实现，`openapi/` 留位） | 免申请、免审核；相比 RN 路线的两大质变：**(a)** `WKHTTPCookieStore.getAllCookies` 原生可直接读 **httpOnly** 的 `SUB`/`XSRF-TOKEN`，不再依赖"页面脚本能读到"这个未证假设；**(b)** CORS 只是浏览器安全模型，**URLSession 上传天然不受限**，只需按服务端校验补齐 Referer/Origin 头。代价不变 = 风控长期维护（R1）+ WebView 常驻内存 |

### 2.2 仓库结构（规划）

```
my-weibo-app/
├── project.yml                 # XcodeGen 工程定义（pbxproj 为生成产物）
├── Sources/
│   ├── App/                    # @main、TabView 壳、导航 Route、Theme、DI 组装根
│   ├── Features/               # 按功能域切分
│   │   ├── Auth/               # 登录（WKWebView 扫码）、会话检测、登出
│   │   ├── Timeline/           # 关注/推荐时间线
│   │   ├── Compose/            # 发布微博（文字/图片/话题）
│   │   ├── Detail/             # 微博详情、评论、转发、点赞
│   │   ├── Profile/            # 用户主页、关注列表
│   │   ├── Search/             # 搜索、热搜
│   │   └── Notifications/      # 消息中心
│   ├── Core/
│   │   ├── WebViewChannel/     # 离屏 WKWebView 宿主、双车道、限流 actor、风控降级
│   │   ├── APIWeb/             # Web 端点定义、DTO、分页游标（改版只动这里）
│   │   ├── Store/              # 偏好/草稿/搜索历史 KV（凭证永不落 App 存储）
│   │   └── UI/                 # 共享组件 + Material 视觉层
│   └── Resources/              # Assets.xcassets / Localizable
├── Tests/                      # XCTest：单元 + 契约快照
├── Scripts/  docs/
```

---

## 3. 风险与前置条件（开工前必读）

| # | 风险 | 影响 | 缓解措施 |
|---|---|---|---|
| **R1** | **Web 接口属未授权通道**：违反微博用户协议（禁止自动化方式未授权访问）；风控随时升级——432 限频、滑块、字段变更是常态（参见 [weibo-crawler 的 432 实例](https://github.com/dataabc/weibo-crawler/issues/565)） | 高（合规）/ 中（工程） | ① 定位个人开源演示：**不上架、不商用、不批量抓取/存库**；② 全局限流（间隔 ≥1s、并发 ≤2，用 actor 实现）+ 缓存，新鲜度让位于低调；③ 触发风控时唤起可见 WKWebView 让用户人工验证后自动重放；④ 端点全部收敛在 `Core/APIWeb/`，改版只动一处；⑤ README 显著位置放免责声明 |
| **R2** | Web 会话维护：扫码登录、Cookie 过期、多端登录互踢 | 中 | 登录统一在嵌入式 WKWebView 人工完成（App 不碰账密/加密参数）；请求命中 401/跳登录页即自动唤起重新登录；会话持久化依赖 `WKWebsiteDataStore.default()`，模拟器与真机分别实测 |
| **R6** | 长列表 + 富文本 + 图片在老款 iPhone 上性能未经检验（SwiftUI List/LazyVStack 海量图文的回收与解码抖动） | 低–中 | M2 结束前做 1k 条时间线滚动压测（Instruments + 真机帧率） |
| **R7** | 路线 B 地基在**原生语境**下重述，四个待证点：① 离屏/隐藏的 WKWebView 是否被挂起（原生已知解法：入屏 1×1 视图或独立 UIWindow，需实测）；② 页面内 fetch 经消息桥回传在 App 前后台切换/锁屏恢复后的存活；③ `WKHTTPCookieStore` 读到含 httpOnly 的 `SUB`/`XSRF-TOKEN` 并成功附带；④ 原生 URLSession 直传上传域名时服务端的 Referer/Origin/参数校验行为 | 中（原 RN 时代为高：①②是原生成熟技巧，③④相比"JS 能否读到 httpOnly"与"页面内 fetch 撞 CORS"根本是确定性提升）| M0 首个 spike 四项判据全过才算通过；失败处置：①②失败→常驻可见层级小窗；③失败→回车道①（页面内取数含附带）；④失败→上传/发布改走可见 WKWebView 内完成 |

> 注：R3（RN ↔ RN macOS 版本对齐）已随 macOS 平台移除、R4（三方库跨端覆盖）已收缩进 §7、R5 已随 Windows 平台移除；RN 整体时代的通道与架构风险随技术栈切换一并退场——编号有意不回排，以保持 R6/R7 引用稳定；D2/D3、M8 同理。

**开工前核对：**

- [ ] 项目定位确认：个人学习/开源演示，GitHub 分发，不上架、不商用、不批量抓取
- [ ] 已通读微博用户协议相关条款，README 免责声明文案备好
- [ ] 个人微博账号 Web 端扫码登录正常，作为开发验证账号
- [ ] **路线 B 原生 spike 通过，覆盖 R7 全部四项判据**（隐藏常驻/桥回传存活/Cookie 直读/上传校验）（M0 首项）
- [ ] 已盘点设备：Mac（Xcode ≥ 16）× 1、iPhone 真机 × 1
- [ ] Xcode / Swift / 最低 iOS 版本记录到 `docs/VERSIONS.md`

---

## 4. 环境搭建 Checklist

### 4.1 通用

- [ ] Xcode（≥ 16）+ Command Line Tools
- [ ] XcodeGen 安装（`brew install xcodegen`）+ `project.yml` 跑通
- [ ] SwiftLint + SwiftFormat 配置并接入 pre-commit
- [ ] Git 仓库初始化 + `.gitignore`（构建产物、生成的 xcodeproj）

### 4.2 iOS

- [ ] 模拟器运行 SwiftUI Hello World 成功
- [ ] 真机签名（开发者账号）配置完成，能装能调试
- [ ] 确认目标机型与最低 iOS 版本（iOS 17 起步？见 D1 备注）

---

## 5. 架构基线 Checklist（M0 出口条件）
- [ ] `xcodegen generate` → 工程打开即跑，模拟器/真机启动同一 App
- [ ] SPM 依赖锁定（`Package.swift`/工作区），无 CocoaPods 残留
- [ ] `Core/WebViewChannel`：协议 `WebViewChannel { func fetch(_:) async throws -> Data }` + 双实现（页面内 fetch 车道 / 原生 URLSession 车道）+ **限流 actor**（间隔 ≥1s、并发 ≤2）+ 超时/重试/统一错误模型（`APIError` enum 含 `.punished` case）
- [ ] 风控降级链路：识别 punish/验证码响应 → 唤起可见 WKWebView 人工验证 → 自动重放失败请求
- [ ] `Core/APIWeb`：端点注册表 + DTO（`Codable`）骨架，`openapi/` 留位
- [ ] 存储层：偏好/草稿/搜索历史 KV 封装；**登录凭证不落 App 存储**（Cookie 只存在于系统 WebKit CookieJar）
- [ ] 日志 `os.Logger` 按子系统分域 + Sentry 占位
- [ ] 导航壳：`TabView` + 各 tab 内 `NavigationStack`，集中 Route enum
- [ ] 主题：`Color` 资源 + light/dark 跟随系统；Material 视觉层基础样式（导航栏 `.ultraThinMaterial`）
- [ ] 测试基建：XCTest target 空跑通 + CI lint/typecheck/test
- [ ] `docs/ARCHITECTURE.md` 记录 D1–D9 决策与理由（含废弃项说明）

---

## 6. 功能里程碑

### M1 · 登录与会话

依赖：M0 的路线 B spike（R7）通过。

- [ ] `WebViewChannel` 基座：常驻离屏 WKWebView（保持 weibo.com 源）、`evaluateJavaScript` 注入 fetch + `WKScriptMessageHandlerWithReply` 回传（请求 ID ↔ 回包关联）、并发队列；隐藏态/前后台切换/锁屏恢复存活实测通过（R7 判据①②）
- [ ] 登录窗口：sheet 内嵌可见 WKWebView 打开微博**扫码登录页**，用户人工完成（含滑块/短信验证），App 全程不接触账密
- [ ] 会话检测：轻量端点探测登录态（原生车道带 Cookie 直发）；过期自动唤起重新登录
- [ ] Cookie 同步：`WKHTTPCookieStore` 读取（含 httpOnly）→ 注入 `HTTPCookieStorage.shared`，原生车道自动携带（R7 判据③）
- [ ] "当前账号"全局状态（`@Observable` UserSession）
- [ ] 退出登录：登出 + `WKWebsiteDataStore.default().removeAllData()`
- [ ] 重启后会话恢复验证（系统 CookieJar 持久化，模拟器 + 真机实测）
- [ ] DoD：扫码登录 → 重启保持会话 → 登出后需重新登录

### M2 · 时间线

- [ ] 数据层：关注时间线 Web 端点封装（weibo.com ajax 为主、m.weibo.cn container 兜底，端点以实测为准并全部收敛在 `Core/APIWeb/`）+ 未登录空态
- [ ] 节流与缓存落地：限流 actor 生效、Repository 层 staleTime + 磁盘缓存（**降低风控触发概率优先于数据新鲜度**）
- [ ] 微博 Cell 组件：头像、昵称、认证标识、时间（相对时间）、来源、正文（@/话题/链接富文本，`AttributedString` 分段着色可点击）、配图九宫格
- [ ] 下拉刷新 + 无限滚动分页（游标参数以 Web 端点实测为准）
- [ ] 图片加载 spike：`wx*.sinaimg.cn` 是否需要伪造 Referer、Kingfisher/`AsyncImage` 自定义请求头实测（与 §7 图片库验证合并）
- [ ] 图片查看器（全屏、缩放、翻页；`matchedGeometryEffect` 列表→详情转场）
- [ ] 视频卡片（内联预览 + 点击进入播放，AVKit 系统能力，无跨端之忧）
- [ ] **毛玻璃导航栏**：`.toolbarBackground(.ultraThinMaterial)` + scrollEdge 行为；浮动发博按钮 Material 底
- [ ] 长列表性能：滚动 1k 条记录，iPhone 真机 ≥ 50fps（Instruments 定位解码抖动，图片降采样）
- [ ] 骨架屏与空态/错误态
- [ ] DoD：真机流畅刷微博，转发微博与图片时间线渲染正确

### M3 · 发布微博

- [ ] 发布编辑器：正文输入（140/长文提示）、计数、键盘工具栏
- [ ] 图片选择：`PhotosPicker`（系统选择器，免相册权限读图）+ 多选
- [ ] 上传走**原生车道②**：URLSession multipart + 同步的 Cookie + Referer/Origin 补全（R7 判据④实测为准）；失败预案 = 上传/发布改走可见 WKWebView 内完成
- [ ] 话题 #xx# 插入、@ 好友（可选 P1）
- [ ] 发送中状态、失败重试、草稿本地保存（Store 层）
- [ ] 发布成功后时间线插入新条目
- [ ] DoD：能发纯文本 + 带图微博并立即可见

### M4 · 详情与互动

- [ ] 微博详情页：原文全文、话题链接、来源、发布时间绝对值
- [ ] 评论列表（分页）+ 发评论 + 评论回复楼
- [ ] 转发（直接转发 + 带意见转发）
- [ ] 点赞/取消点赞（乐观更新，失败回滚）
- [ ] 长按操作菜单：系统 `.contextMenu`（转发/评论/点赞/复制/收藏/分享）
- [ ] 收藏（若 API 可得，否则记 P2）
- [ ] DoD：从时间线进入详情，完成一次"评论 + 转发 + 点赞"闭环

### M5 · 用户主页与关注

- [ ] 个人主页：资料卡（头像/简介/粉丝/关注数/微博数）、微博列表、更多列表（图片/视频 tab，`TabView(.page)`）
- [ ] 关注 / 取关（乐观更新 + 回滚）
- [ ] 我的主页 + 编辑资料入口（P1）
- [ ] 他人主页的重定向（短链 `weibo.cn` 解析，P1）
- [ ] DoD：从任意微博可跳到作者主页并关注/取关

### M6 · 搜索与热搜

- [ ] 搜索页：微博/用户/话题 三个 tab，`.searchable` 修饰符 + 提交/取消语义
- [ ] 热搜榜（Web 端侧边热搜数据）+ 点击进搜索结果
- [ ] 搜索历史（本地存储）、防抖请求、`.task(id:)` 竞态取消
- [ ] DoD：可搜索并分页展示结果

### M7 · 消息中心（P1）

- [ ] 三类通知列表：@我、评论、转发（未读角标 `badge`）
- [ ] 点击进入对应微博并高亮锚点
- [ ] 私信：Web 聊天接口实现成本高且敏感 → 首版仍降级为"跳网页版"，P2 再评估
- [ ] 下拉刷新 + 轮询未读数（App 前台时，场景相位驱动）
- [ ] DoD：收到 @ 与评论后消息页可见，跳转正确

### M8 ·（已废弃）

> M8 原为桌面端专项打磨（macOS），随平台与技术栈移除而废弃；保留编号以稳定 M9 与 §10 的引用。

### M9 · 质量与发布

- [ ] 执行 §8.1 测试、§8.2 CI/CD、§8.3 发布通道全部条目，DoD 见 §9

---

## 7. 依赖清单（Swift 工程：能少则少，系统优先）

| 库 | 用途 | 结论/备注 |
|---|---|---|
| WKWebView / URLSession / AVKit | 通道、网络、播放 | 系统自带，零依赖 |
| Kingfisher | 图片加载 + 缓存 + 自定义请求头 | M2 spike 与 Referer 实测一起定；失败退 `URLSession` 手写缓存 |
| swift-snapshot-testing | 端点契约快照 + 关键视图快照 | 微博改字段第一时间发现 |
| Sentry Cocoa SDK | 崩溃与日志上报 | 占位即可，遵守"日志不含凭证"红线 |
| KeychainAccess（或原生 Security） | — | 路线 B 下基本不需要（凭证留在 WebKit CookieJar）；仅存其他敏感信息时再引 |
| swiftlint / swiftformat | 静态检查与格式化 | 工具链，不进包体 |
|（新库按需追加）| | |

- [ ] 准入三问：系统能力是否覆盖？是否可被 20 行薄封装替代？维护活跃度与 SPM 支持如何？
- [ ] 所有网络入口收敛到 `WebViewChannel` 协议，任何库不得绕行限流器直接发请求

---

## 8. 测试与 CI/CD Checklist

### 8.1 测试

- [ ] 单元测试：`APIWeb` DTO 解码、限流 actor（间隔/并发/退避/去重）、Repository 分页游标、Store 层（目标行覆盖 ≥ 70%）
- [ ] 视图测试：关键 View 的编译期构造 + snapshot-testing 视觉回归（Cell、详情页）
- [ ] Mock：以 `WebViewChannel` 协议为注入边界做 fake（回放 Web 端点契约 JSON），UI 测试不依赖真微博
- [ ] 契约快照测试：关键端点响应留快照，微博改字段第一时间发现
- [ ] E2E（P2）：XCUITest 覆盖登录→刷→发主链路（模拟器稳定性一般，主回归靠单测 + 手工矩阵）
- [ ] 手工回归：6 关键流程，每次发版在 iPhone 真机全量执行 + 模拟器冒烟
- [ ] 机型矩阵：最新款 + 一代老款 iPhone（含小屏 SE 类）走查一遍
- [ ] 性能专项：1k 条滚动帧率 + 内存水位（图片解码降采样验证）、冷启动 < 2s

### 8.2 CI/CD（GitHub Actions）

- [ ] PR 门禁：swiftlint + swiftformat --lint + 编译 + 单测（macos runner 上 `xcodebuild test`）
- [ ] `ios.yml`：xcodegen → 模拟器构建 → 跑契约快照
- [ ] 版本与 Changelog 自动化（semantic-release 或手动 tag）
- [ ] 制品归档：`.ipa`/`.app` 构建产物落到 Release 页

### 8.3 发布通道

- [ ] iOS：本机自签分发（Xcode 签名，免费账号 7 天重签；日常主力机使用时建议付费开发者账号，签名有效期 ≥1 年），README 附"clone → xcodegen → 运行"三步说明。**不用 TestFlight**——其外测需过 App Store Connect Beta 审核，与 §1.1"不上架"及 R1 低调姿态冲突；仅限直连设备安装
- 注：分发完全锁在 Apple 签名体系内；历史上多端（Android 最廉价分发、macOS 共享 Darwin）与 RN 方案的完整论证见 git 历史

---

## 9. 验收标准（整体 DoD）

- [ ] iOS 首版安装包可在干净环境（clone + xcodegen + 签名，或 CI 产物）安装运行
- [ ] M1–M5 全部 P0 功能真机走查通过，截图/录屏留档到 `docs/reviews/`
- [ ] 冷启动 < 2s（基准机型）；时间线滚动 ≥ 50fps（iPhone 真机）
- [ ] 毛玻璃导航栏/浮层在 light/dark 下渲染正确，无滚动抖动
- [ ] 崩溃率：内部测试期无阻断性崩溃；离线/弱网有明确降级 UI
- [ ] 登录凭证仅存于系统 WebKit CookieJar；App 自有存储与日志中无任何 Cookie/凭证
- [ ] README 显著位置含免责声明与使用限制（个人学习用途、低频访问、尊重服务器），与 R1 缓解措施一致
- [ ] `README.md` 含从零跑起来的一句话命令；`docs/ARCHITECTURE.md`、`docs/VERSIONS.md` 与实现一致
- [ ] 已知限制清单（如私信降级、部分接口权限）在 README 显著位置声明

---

## 10. 里程碑顺序与出口条件

> 本计划不附工期估算：执行主体为 AI，瓶颈在**验收吞吐与外部依赖**（微博风控行为、接口改版、扫码/滑块与真机走查等人工环节），周数估算没有意义。要紧的是推进顺序与出口条件——顺序仍然重要，因为下游里程碑依赖上游的通道基座与实证结论。

| 阶段 | 内容 | 出口条件 |
|---|---|---|
| M0 | 环境与架构基线（§4、§5、§7 spike） | Hello World 双环境可跑 + 版本锁定 + 依赖清单 + **R7 四项判据全过** |
| M1 | 登录与会话（WebViewChannel 基座） | 扫码登录 + 双车道通道稳定 + 会话重启恢复 |
| M2 | 时间线 | 真机刷微博 + 性能达标 + 毛玻璃导航落地 |
| M3 | 发布微博 | 发文（含图）闭环 |
| M4 | 详情与互动 | 评论/转发/点赞闭环 |
| M5 | 主页与关注 | 关注闭环 |
| M6 | 搜索与热搜 | 三 tab 搜索 + 热搜可用 |
| M7 | 消息中心（P1） | 通知列表可用 |
| M8 | （已废弃，保留编号） | — |
| M9 | 测试收尾、CI/CD、发布 | §9 全部通过 |

> 关键路径：M0 的**路线 B 原生 spike（R7）**仍是全局地基，但风险已从"高"降到"中"——隐藏 WebView 常驻、Cookie 直读、原生上传都是有大量先例的原生技巧，不像 RN 时代隔着 JS 桥赌两个未证假设。任一判据失败按 R7 缓解列逐项处置，必须在 M0 收尾时定案，不带病进入 M1。AI 执行下 spike 本身跑得很快，但登录扫码、滑块验证、真机走查是天然的人工环节，**验收排队可能取代编码成为新瓶颈**，每个里程碑 DoD 应设计成可一次性批量验收的形态。

---

## 11. 参考资料

- SwiftUI 文档：<https://developer.apple.com/documentation/swiftui>
- WebKit / WKWebView 文档：<https://developer.apple.com/documentation/webkit>
- Swift Package Manager：<https://www.swift.org/documentation/package-manager/>
- XcodeGen：<https://github.com/yonaskolb/XcodeGen>
- 微博开放平台文档（备用通道参考）：<https://open.weibo.com/wiki/Mainpage>
- Web 接口现状参考：[weibo-crawler（432 风控实例）](https://github.com/dataabc/weibo-crawler/issues/565)、[weibo-api-sdk（m 站免登录封装）](https://github.com/shibing624/weibo-api-sdk)、[RSSWorker 微博订阅生成器](https://github.com/yllhwa/RSSWorker)
