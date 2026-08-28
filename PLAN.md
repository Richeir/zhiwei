# 新浪微博客户端（React Native · iOS）项目计划

> 目标：用 React Native 构建一个微博客户端，首版**只做 iOS**。架构保持分层与通道抽象（D9），为日后恢复桌面/多端留好退路（历史平台取舍见 git 记录）。
>
> 交付物约定：每个里程碑（Mx）都有验收标准（DoD）与可勾选的任务清单。

---

## 1. 项目概述

| 项 | 内容 |
|---|---|
| 产品形态 | 新浪微博第三方客户端（iOS） |
| 技术栈 | React Native（Bare）+ TypeScript |
| 平台 | iOS |
| 数据来源 | **微博 Web 端接口**（无需开放平台申请；路线 B：隐藏 WebView 同源代理，见 D9；合规约束见 R1） |
| 执行方式 | **AI 全量执行**（编码、测试脚手架、CI 配置）；人负责验收走查、真机操作与风控人工验证环节 |

### 1.1 产品目标（P0 = 首版必须，P1 = 首版尽量，P2 = 后续迭代）

- [ ] 项目定位：**个人学习 / 开源演示**，仅 GitHub 分发，不上架商店、不商用、不批量抓取（路线 B 的合规前提，见 R1）
- [ ] P0 能登录、看时间线、刷微博、发微博
- [ ] P0 微博详情：正文、图片/视频、评论、转发、点赞
- [ ] P0 个人主页：用户资料、微博列表、关注/取关
- [ ] P1 搜索（微博/用户/话题）与热搜榜
- [ ] P1 消息中心（@我、评论、转发通知）
- [ ] P2 私信、长文、视频直播、九宫格发布时间优化、小组件等

---

## 2. 技术方案总览

### 2.1 关键决策

| # | 决策点 | 选择 | 理由 / 备选 |
|---|---|---|---|
| D1 | 脚手架 | **Bare React Native CLI**（`@react-native-community/cli`） | 对原生工程全控：WKWebView Cookie 管理、相册等小原生桥直写原生层；iOS-only 下 Expo 也是合理备选，若无新需求默认 Bare（M0 定案，不阻塞） |
| D2 | 桌面端框架 | —（已废弃） | 原选 react-native-macos，随 macOS 平台移除而废弃；若恢复桌面端，重新评估 react-native-macos 与 Swift 原生两条路线 |
| D3 | 多平台组织 | —（已废弃） | iOS 单平台，平台扩展文件（`*.ios.tsx` 变体）失去存在理由，不引入；共享逻辑照常放 `src/` |
| D4 | 新架构（Fabric/TurboModules） | **直接采用 New Architecture** | RN 0.76+ 起默认开启，iOS 侧支持成熟；此前的"跨端节奏不同步"顾虑（原 R3）随 macOS 移除消失 |
| D5 | 导航 | React Navigation：**Native Stack（react-native-screens）+ Bottom Tabs** | 移除 RN macOS 后 native-stack 可用，转场与手势更贴近系统原生 |
| D6 | 状态与数据 | Zustand（UI 状态）+ TanStack Query（服务端数据）+ `WebViewChannel` 页面内 fetch（替代 Axios，见 D9） | 轻量、纯 TS |
| D7 | UI 组件 | 自建薄组件层 + React Native Paper（可选主题层） | 只针对移动端交互模型设计，无需桌面差异适配层 |
| D8 | 语言 | TypeScript 全覆盖 | — |
| D9 | **数据通道（路线 B）** | App 常驻**离屏 WebView**（保持已登录的 weibo.com 同源会话），所有 API 调用经 `injectJavaScript` 在**页面内发起 `fetch`**；`src/api/` 保留后端抽象（`web/` 默认实现，`openapi/` 留位） | 免申请、免审核，接口能力即网页全量能力；Cookie（含 httpOnly 的 `SUB`）由系统 WebView CookieJar 管理，App 不写 Cookie 桥；`X-XSRF-TOKEN` 等参数预期可由页面脚本读取后附带（httpOnly 与否待 R7 判据③实证）；代价 = 风控长期维护（R1）+ WebView 常驻内存 |

### 2.2 仓库结构（规划）

```
my-weibo-app/
├── index.js                    # 入口，注册 AppRegistry（单 target）
├── package.json                # scripts（start/ios）
├── ios/                        # RN iOS 工程（CocoaPods）
├── src/
│   ├── app/                    # App 组装：导航容器、主题、Provider
│   ├── features/               # 按功能域切分
│   │   ├── auth/               # 登录（WebView 扫码会话）、会话检测、登出
│   │   ├── timeline/           # 关注/推荐时间线
│   │   ├── compose/            # 发布微博（文字/图片/话题/位置）
│   │   ├── detail/             # 微博详情、评论、转发、点赞
│   │   ├── profile/            # 用户主页、关注列表
│   │   ├── search/             # 搜索、热搜
│   │   └── notifications/      # 消息中心
│   ├── api/                    # 数据层：WebViewChannel 通道、web/ 端点定义、DTO、节流与缓存
│   ├── components/             # 共享 UI 组件（Cell、Avatar、RichText…）
│   ├── stores/  hooks/  utils/  assets/  theme/
└── __tests__/  scripts/  docs/
```

---

## 3. 风险与前置条件（开工前必读）

| # | 风险 | 影响 | 缓解措施 |
|---|---|---|---|
| **R1** | **Web 接口属未授权通道**：违反微博用户协议（禁止自动化方式未授权访问）；风控随时升级——432 限频、滑块、字段变更是常态（参见 [weibo-crawler 的 432 实例](https://github.com/dataabc/weibo-crawler/issues/565)） | 高（合规）/ 中（工程） | ① 定位个人开源演示：**不上架、不商用、不批量抓取/存库**；② 全局限流（间隔 ≥1s、并发 ≤2）+ 缓存，新鲜度让位于低调；③ 触发风控时唤起可见 WebView 让用户人工验证后自动重放；④ 端点全部收敛在 `src/api/web/`，改版只动一处；⑤ README 显著位置放免责声明 |
| **R2** | Web 会话维护：扫码登录、Cookie 过期、多端登录互踢 | 中 | 登录统一在嵌入式 WebView 人工完成（App 不碰账密/加密参数）；请求命中 401/跳登录页即自动唤起重新登录；会话持久化依赖系统 CookieJar，模拟器与真机分别实测 |
| **R6** | 长列表 + 富文本 + 图片在老款 iPhone 上性能未经检验 | 低–中 | M2 结束前做 1k 条时间线滚动压测，真机记录 FPS |
| **R7** | `react-native-webview` 的"离屏常驻 + 页面内 fetch"模式稳定性未实测。两个隐含假设同样待证：① WKWebView 脱离视图树/0×0 时 JS 可能被挂起，"离屏常驻"可能需 1×1 透明常驻视图等技巧；② 上传接口在跨域域名，页面内 fetch 可能撞 CORS | 高（路线 B 地基） | M0 首个 spike 在 iOS（模拟器 + 真机）验证，**四项判据全过才算通过**：① 隐藏 WebView 加载 weibo.com → 注入 fetch → 取回 JSON；② 隐藏态、前后台切换、锁屏恢复后通道仍可用；③ 页面内 POST 能读取并附带 `X-XSRF-TOKEN`；④ 上传端点跨域行为实测。任一失败即触发方案评审：回退"原生 Cookie 桥 + 直连 HTTP"（WKWebView 非 httpOnly Cookie 的可读边界需实测），或上传/发布改走可见 WebView |

> 注：R3（RN ↔ RN macOS 版本对齐）已随 macOS 平台移除、R4（三方库跨端覆盖）已收缩进 §7 矩阵、R5 已随 Windows 平台移除——编号有意不回排，以保持 R6/R7 在下文的引用稳定；D2/D3、M8 同理。

**开工前核对：**

- [ ] 项目定位确认：个人学习/开源演示，GitHub 分发，不上架、不商用、不批量抓取
- [ ] 已通读微博用户协议相关条款，README 免责声明文案备好
- [ ] 个人微博账号 Web 端扫码登录正常，作为开发验证账号
- [ ] `react-native-webview` 离屏代理 spike 通过，覆盖 R7 全部四项判据（含隐藏常驻与上传跨域）（M0 首项）
- [ ] 已盘点设备：Mac（Xcode ≥ 15）× 1、iPhone 真机 × 1
- [ ] RN 基准版本记录到 `docs/VERSIONS.md`

---

## 4. 环境搭建 Checklist

### 4.1 通用

- [ ] Node LTS（与 RN CLI 要求匹配）+ Corepack/Yarn
- [ ] React Native DevTools / `npx react-native doctor` 全绿
- [ ] Git 仓库初始化 + `.gitignore`（iOS 构建产物）
- [ ] 编辑器配置：TS、ESLint、Prettier 统一

### 4.2 iOS

- [ ] Xcode + Command Line Tools + CocoaPods + Watchman
- [ ] 模拟器运行 Hello World 成功
- [ ] 真机签名（开发者账号）配置完成

---

## 5. 架构基线 Checklist（M0 出口条件）
- [ ] `npx @react-native-community/cli init` 生成基础工程，iOS 壳工程可启动（New Architecture 开启）
- [ ] `package.json` scripts：`start` / `ios` 一键可用
- [ ] `index.js` 中 `AppRegistry` 注册正确，模拟器/真机渲染同一 `<App/>`
- [ ] TypeScript 严格模式 + 路径别名 `src/*`
- [ ] 主题系统：light/dark 跟随系统
- [ ] 数据通道层：`WebViewChannel`（常驻离屏 WebView + 页面内 `fetch`，请求 ID ↔ 回包关联）+ 超时/重试/统一错误模型 + **全局限流器**（间隔 ≥1s、并发 ≤2）
- [ ] 风控降级链路：识别 punish/验证码响应 → 唤起可见 WebView 人工验证 → 自动重放失败请求
- [ ] 存储层封装：KV（`@react-native-async-storage/async-storage`），仅存偏好/草稿/搜索历史；**登录凭证一律不落 App 存储**（Cookie 只存在于系统 WebView CookieJar）
- [ ] 日志与崩溃上报占位（Sentry iOS 支持随 spike 确认）
- [ ] 导航容器：Bottom Tabs + Native Stack，Route 定义集中一处
- [ ] ESLint + Prettier + Husky（pre-commit）+ `jest` 空跑通
- [ ] `docs/ARCHITECTURE.md` 记录 D1–D9 决策与理由（含废弃项说明）

---

## 6. 功能里程碑

### M1 · 登录与会话

依赖：M0 的 WebView spike（R7）通过。

- [ ] `WebViewChannel` 基座：常驻离屏 WebView（保持 weibo.com 源）、页面内 fetch 封装、请求 ID ↔ 回包关联、并发队列；隐藏态/前后台切换/锁屏恢复存活测试通过（R7 判据②）
- [ ] 登录窗口：内嵌 WebView 打开微博**扫码登录页**，用户人工完成（含滑块/短信验证），App 全程不接触账密
- [ ] 会话检测：轻量端点探测登录态；过期自动唤起重新登录
- [ ] "当前账号"全局状态（页面内 GET 自己的 profile → Zustand store）
- [ ] 退出登录：登出 + 清理 WebView 会话/Cookie（`WKWebsiteDataStore` 原生桥）
- [ ] 重启后会话恢复验证（依赖系统 CookieJar 持久化，模拟器 + 真机实测）
- [ ] DoD：扫码登录 → 重启保持会话 → 登出后需重新登录

### M2 · 时间线

- [ ] 数据层：关注时间线 Web 端点封装（weibo.com ajax 为主、m.weibo.cn container 兜底，端点以实测为准并全部收敛在 `src/api/web/`）+ 未登录空态
- [ ] 节流与缓存落地：全局限流生效、TanStack Query staleTime + 本地缓存（**降低风控触发概率优先于数据新鲜度**）
- [ ] 微博 Cell 组件：头像、昵称、认证标识、时间（相对时间）、来源、正文（含 @/话题/链接富文本渲染）、配图九宫格
- [ ] 下拉刷新 + 无限滚动分页（游标参数以 Web 端点实测为准）
- [ ] 图片加载 spike：`wx*.sinaimg.cn` 是否需要伪造 Referer、RN `Image` headers 在 iOS 的支持实测（与 §7 图片库验证合并）
- [ ] 图片查看器（全屏、缩放、翻页）
- [ ] 视频卡片（内联预览 + 点击进入播放；iOS 可直接接 `react-native-video`（AVPlayer），无需再降级为外链——列为 P1）
- [ ] 长列表性能：滚动 1k 条记录，iPhone 真机帧率 ≥ 50fps
- [ ] 骨架屏与空态/错误态
- [ ] DoD：真机流畅刷微博，转发微博与图片时间线渲染正确

### M3 · 发布微博

- [ ] 发布编辑器：正文输入（140/长文提示）、计数
- [ ] 图片选择与多选上传（相册权限 + PHPicker）
- [ ] 话题 #xx# 插入、@ 好友（可选 P1）
- [ ] 发送走页面内 POST：`X-XSRF-TOKEN` 由页面脚本读取后附带（可读性以 M0 spike R7 判据③实证为准，非天然保证）；失败预案 = 上传/发布改走可见 WebView 内完成
- [ ] 发送中状态、失败重试、草稿本地保存
- [ ] 发布成功后时间线插入新条目
- [ ] DoD：能发纯文本 + 带图微博并立即可见

### M4 · 详情与互动

- [ ] 微博详情页：原文全文、话题链接、来源、发布时间绝对值
- [ ] 评论列表（分页）+ 发评论 + 评论回复楼
- [ ] 转发（直接转发 + 带意见转发）
- [ ] 点赞/取消点赞（乐观更新）
- [ ] 长按操作菜单（Cell 级动作：转发/评论/点赞/复制/收藏）
- [ ] 收藏（若 API 可得，否则记 P2）
- [ ] DoD：从时间线进入详情，完成一次"评论 + 转发 + 点赞"闭环

### M5 · 用户主页与关注

- [ ] 个人主页：资料卡（头像/简介/粉丝/关注数/微博数）、微博列表、更多列表（图片/视频 tab）
- [ ] 关注 / 取关（乐观更新 + 回滚）
- [ ] 我的主页 + 编辑资料入口（P1）
- [ ] 他人主页的重定向（短链 `weibo.cn` 解析，P1）
- [ ] DoD：从任意微博可跳到作者主页并关注/取关

### M6 · 搜索与热搜

- [ ] 搜索页：微博/用户/话题 三个 tab（Web 端搜索能力完整，直接全量落地，无开放平台权限之困）
- [ ] 热搜榜（Web 端侧边热搜数据）+ 点击进搜索结果
- [ ] 搜索历史（本地存储）、防抖请求、竞态取消
- [ ] DoD：可搜索并分页展示结果

### M7 · 消息中心（P1）

- [ ] 三类通知列表：@我、评论、转发（未读角标）
- [ ] 点击进入对应微博并高亮锚点
- [ ] 私信：Web 聊天接口实现成本高且敏感 → 首版仍降级为"跳网页版"，P2 再评估
- [ ] 下拉刷新 + 轮询未读数（App 前台时）
- [ ] DoD：收到 @ 与评论后消息页可见，跳转正确

### M8 ·（已废弃）

> M8 原为桌面端专项打磨（macOS），随平台移除而废弃；保留编号以稳定 M9 与 §10 的引用。

### M9 · 质量与发布

- [ ] 执行 §8.1 测试、§8.2 CI/CD、§8.3 发布通道全部条目，DoD 见 §9

---

## 7. 依赖准入矩阵（引入任何三方库前填一行）

| 库 | 结论/状态 |
|---|---|
| react-native (core) | 基准版本锁 `docs/VERSIONS.md` |
| react-native-screens + @react-navigation/* | ✅ iOS 支持成熟；M0 随工程实测 |
| @react-native-async-storage/async-storage | ✅ 官方支持 |
| zustand / @tanstack/query | ✅ 纯 JS |
| react-native-webview | ✅（iOS 为第一优先平台）；**路线 B 核心依赖**，四项判据以 M0 首要 spike 实测为准（R7） |
| expo-image / fast-image | spike 验证（与 M2 图片加载/Referer 实测合并），失败则 RN `Image` + 手动缓存 |
| react-native-gesture-handler | ✅ 新架构支持成熟；图片查看器手势用 |
| react-native-keychain | 路线 B 下基本不再需要（凭证留在 WebView CookieJar）；仅当要存其他敏感信息时重新评估 |
| react-native-video | 可选（M2 视频播放器，P1） |
|（新库按需追加）| |

- [ ] 每行状态在 M0 spike 中实测更新，不允许"未验证直接引入"
- [ ] 所有 ⚠️/❌ 项都有接口抽象，不被具体库绑架
- 注：准入矩阵的原价值是平台覆盖筛选；iOS-only 后收缩为**维护活跃度与 New Architecture 适配**两项检查

---

## 8. 测试与 CI/CD Checklist

### 8.1 测试

- [ ] 单元测试：API 层、stores、utils（目标行覆盖 ≥ 70%）
- [ ] 组件测试：`@testing-library/react-native` 覆盖核心 Cell/详情页
- [ ] Mock：以 `WebViewChannel` 为注入边界做 fake（回放 Web 端点契约 JSON），UI 测试不依赖真微博
- [ ] 契约快照测试：关键端点响应留快照，微博改字段第一时间发现
- [ ] 节流器单测：限流、退避、请求去重
- [ ] E2E（P2）：Maestro 覆盖登录→刷→发主链路（模拟器稳定性偏弱，主回归依赖手工矩阵）
- [ ] 手工回归：6 关键流程，每次发版在 iPhone 真机全量执行 + 模拟器冒烟
- [ ] 机型矩阵：最新款 + 一代老款 iPhone（含小屏 SE 类）走查一遍

### 8.2 CI/CD（GitHub Actions）

- [ ] PR 门禁：lint + typecheck + 单测
- [ ] `ios.yml`：pod install + 模拟器构建（fastlane）
- [ ] 版本与 Changelog 自动化（semantic-release 或手动 tag）
- [ ] 制品归档：iOS 构建产物落到 Release 页

### 8.3 发布通道

- [ ] iOS：本机自签分发（Xcode 签名，免费账号 7 天重签；日常主力机使用时建议付费开发者账号，签名有效期 ≥1 年），README 附编译步骤。**不用 TestFlight**——其外测需过 App Store Connect Beta 审核，与 §1.1"不上架"及 R1 低调姿态冲突；仅限直连设备安装
- 注：iOS-only 后分发完全锁在 Apple 签名体系内；若日后需要他人零门槛试用或恢复桌面端，恢复多端（Android 曾是最廉价分发通道、macOS 曾与 iOS 共享 Darwin 体系）的完整论证记录在 git 历史中

---

## 9. 验收标准（整体 DoD）

- [ ] iOS 首版安装包可在干净环境（CI 产物）安装运行
- [ ] M1–M5 全部 P0 功能真机走查通过，截图/录屏留档到 `docs/reviews/`
- [ ] 冷启动 < 2s（基准机型）
- [ ] 时间线滚动 ≥ 50fps（iPhone 真机）
- [ ] 崩溃率：内部测试期无阻断性崩溃；离线/弱网有明确降级 UI
- [ ] 登录凭证仅存于系统 WebView CookieJar；App 自有存储与日志中无任何 Cookie/凭证
- [ ] README 显著位置含免责声明与使用限制（个人学习用途、低频访问、尊重服务器），与 R1 缓解措施一致
- [ ] `README.md` 含 iOS 从零跑起来的一句话命令；`docs/ARCHITECTURE.md`、`docs/VERSIONS.md` 与实现一致
- [ ] 已知限制清单（如私信降级、部分接口权限）在 README 显著位置声明

---

## 10. 里程碑顺序与出口条件

> 本计划不附工期估算：执行主体为 AI，瓶颈在**验收吞吐与外部依赖**（微博风控行为、接口改版、扫码/滑块与真机走查等人工环节），周数估算没有意义。要紧的是推进顺序与出口条件——顺序仍然重要，因为下游里程碑依赖上游的通道基座与实证结论。

| 阶段 | 内容 | 出口条件 |
|---|---|---|
| M0 | 环境与架构基线（§4、§5、§7 spike） | iOS Hello World + 版本锁定 + 依赖矩阵 + **R7 四项判据全过** |
| M1 | 登录与会话（WebViewChannel 基座） | 扫码登录 + 通道基座稳定 |
| M2 | 时间线 | 真机刷微博 + 性能达标 |
| M3 | 发布微博 | 发文闭环 |
| M4 | 详情与互动 | 评论/转发/点赞闭环 |
| M5 | 主页与关注 | 关注闭环 |
| M6 | 搜索与热搜 | 三 tab 搜索 + 热搜可用 |
| M7 | 消息中心（P1） | 通知列表可用 |
| M8 | （已废弃，保留编号） | — |
| M9 | 测试收尾、CI/CD、发布 | §9 全部通过 |

> 关键路径：M0 的 **WebViewChannel 离屏常驻 spike（R7）** 是路线 B 的地基，四项判据任一失败即触发方案评审（回退"原生 Cookie 桥 + 直连 HTTP"，或上传/发布改走可见 WebView）。该 spike 必须在 M0 收尾时定案，不带病进入 M1。AI 执行下 spike 本身跑得很快，但登录扫码、滑块验证、真机走查是天然的人工环节，**验收排队可能取代编码成为新瓶颈**，每个里程碑 DoD 应设计成可一次性批量验收的形态。

---

## 11. 参考资料

- React Native 文档：<https://reactnative.dev/docs/getting-started>
- 微博开放平台文档（备用通道参考）：<https://open.weibo.com/wiki/Mainpage>
- Web 接口现状参考：[weibo-crawler（432 风控实例）](https://github.com/dataabc/weibo-crawler/issues/565)、[weibo-api-sdk（m 站免登录封装）](https://github.com/shibing624/weibo-api-sdk)、[RSSWorker 微博订阅生成器](https://github.com/yllhwa/RSSWorker)
