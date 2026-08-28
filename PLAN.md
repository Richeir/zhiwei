# 新浪微博客户端（React Native 三平台）项目计划

> 目标：用 React Native 构建一个微博客户端，代码绝大部分共享，一套仓库同时产出 **iOS / Android / macOS** 三个平台的应用。
>
> 文档状态：v3.1 · 评审修订版 · 待评审
> 修订记录：v2 — 放弃开放平台申请路线，改用微博 Web 接口 + WebView 会话代理（D9、R1、R2、R7、M1 相应调整）；v3 — 彻底移除 Windows 平台，聚焦 iOS / Android / macOS，总工期相应压缩；v3.1 — 评审修复：R7 spike 扩为四项判据（隐藏常驻/XSRF 可读/上传跨域）、iOS 分发去 TestFlight 对齐"不上架"口径、依赖矩阵措辞回归"未验证不标已验证"、工期算术与图片 Referer 项补位
> 交付物约定：每个里程碑（Mx）都有验收标准（DoD）与可勾选的任务清单。

---

## 1. 项目概述

| 项 | 内容 |
|---|---|
| 产品形态 | 新浪微博第三方客户端（移动端 + 桌面端） |
| 技术栈 | React Native（Bare）+ react-native-macos |
| 平台 | iOS、Android、macOS |
| 数据来源 | **微博 Web 端接口**（无需开放平台申请；路线 B：隐藏 WebView 同源代理，见 D9；合规约束见 R1） |
| 团队假设 | 1–2 名开发，全栈 RN |
| 总工期估算 | 串行之和 16.5 周；并行后关键路径约 12–14.5 周（详见 §10） |

### 1.1 产品目标（P0 = 首版必须，P1 = 首版尽量，P2 = 后续迭代）

- [ ] 项目定位：**个人学习 / 开源演示**，仅 GitHub 分发，不上架商店、不商用、不批量抓取（路线 B 的合规前提，见 R1）
- [ ] P0 能登录、看时间线、刷微博、发微博
- [ ] P0 微博详情：正文、图片/视频、评论、转发、点赞
- [ ] P0 个人主页：用户资料、微博列表、关注/取关
- [ ] P1 搜索（微博/用户/话题）与热搜榜
- [ ] P1 消息中心（@我、评论、转发通知）
- [ ] P1 桌面端体验优化（键盘快捷键、多栏布局、菜单栏）
- [ ] P2 私信、长文、视频直播、九宫格发布时间优化、小组件等

---

## 2. 技术方案总览

### 2.1 关键决策

| # | 决策点 | 选择 | 理由 / 备选 |
|---|---|---|---|
| D1 | 脚手架 | **Bare React Native CLI**（`@react-native-community/cli`），不用 Expo | Expo 官方 SDK 不覆盖 `react-native-macos` 目标；Bare 模式对三平台 target 控制最完整 |
| D2 | 桌面端框架 | [react-native-macos](https://github.com/microsoft/react-native-macos/releases) | 微软官方维护，与 RN core 同 minor 版本对齐发布；与 iOS 同为 Darwin/CocoaPods 体系，原生桥代码（Cookie、相册、菜单）可大量互抄 |
| D3 | 多平台组织 | 单仓单 App + **平台扩展文件**（`.ios.tsx` / `.android.tsx` / `.macos.tsx` / `.native.tsx`） | 简单直接；共享逻辑放 `src/`，平台壳工程各自独立 |
| D4 | 新架构（Fabric/TurboModules） | 首版按 RN macOS 当前稳定支持情况决定，默认**先跑通旧架构兼容路径，新架构作为 spike** | 见 §3 R3；RN macOS 对 New Architecture 的支持节奏与 core 不同步 |
| D5 | 导航 | React Navigation（JS Stack + Tabs），桌面端切换为**侧边栏导航**布局 | `react-native-screens`/native-stack 在 RN macOS 不可用，统一用 JS 实现保证三端一致 |
| D6 | 状态与数据 | Zustand（UI 状态）+ TanStack Query（服务端数据）+ `WebViewChannel` 页面内 fetch（替代 Axios，见 D9） | 轻量、纯 JS、无原生依赖，天然三平台兼容 |
| D7 | UI 组件 | 自建薄组件层 + React Native Paper（可选主题层） | 避免依赖只支持手机端的组件库；桌面差异用扩展文件处理 |
| D8 | 语言 | TypeScript 全覆盖 | — |
| D9 | **数据通道（路线 B）** | App 常驻**离屏 WebView**（保持已登录的 weibo.com 同源会话），所有 API 调用经 `injectJavaScript` 在**页面内发起 `fetch`**；`src/api/` 保留后端抽象（`web/` 默认实现，`openapi/` 留位） | 免申请、免审核，接口能力即网页全量能力；Cookie（含 httpOnly 的 `SUB`）由原生 CookieJar 管理，无需三端各写 Cookie 桥；`X-XSRF-TOKEN` 等参数预期可由页面脚本读取后附带（httpOnly 与否待 R7 判据③实证）；代价 = 风控长期维护（R1）+ WebView 常驻内存 |

### 2.2 仓库结构（规划）

```
my-weibo-app/
├── index.js                    # 单一入口，注册 AppRegistry（含桌面 target appKey 注册）
├── package.json                # 依赖三平台框架与 scripts（ios/android/macos）
├── ios/                        # RN iOS 工程（CocoaPods）
├── android/                    # RN Android 工程（Gradle）
├── macos/                      # react-native-macos 工程（Xcode + CocoaPods）
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
│   │   └── *.macos.tsx         # 平台差异用扩展文件覆盖
│   ├── desktop/                # 桌面专属：菜单栏、快捷键、多栏布局
│   ├── stores/  hooks/  utils/  assets/  theme/
└── __tests__/  scripts/  docs/
```

---

## 3. 风险与前置条件（开工前必读）

| # | 风险 | 影响 | 缓解措施 |
|---|---|---|---|
| **R1** | **Web 接口属未授权通道**：违反微博用户协议（禁止自动化方式未授权访问）；风控随时升级——432 限频、滑块、字段变更是常态（参见 [weibo-crawler 的 432 实例](https://github.com/dataabc/weibo-crawler/issues/565)） | 高（合规）/ 中（工程） | ① 定位个人开源演示：**不上架、不商用、不批量抓取/存库**；② 全局限流（间隔 ≥1s、并发 ≤2）+ 缓存，新鲜度让位于低调；③ 触发风控时唤起可见 WebView 让用户人工验证后自动重放；④ 端点全部收敛在 `src/api/web/`，改版只动一处；⑤ README 显著位置放免责声明 |
| **R2** | Web 会话维护：扫码登录、Cookie 过期、多端登录互踢 | 中 | 登录统一在嵌入式 WebView 人工完成（App 不碰账密/加密参数）；请求命中 401/跳登录页即自动唤起重新登录；会话持久化依赖系统 CookieJar，三端分别验证 |
| **R3** | 新架构（0.76+ Fabric 默认）与 RN macOS 的支持节奏不完全同步，部分三方库未适配 | 中 | M0 阶段做一次**三平台空工程 spike**，锁定一个 RN core ↔ RN macOS 对齐的 minor 版本再大规模开发 |
| **R4** | 三方库平台覆盖不全（图片库、secure storage、键盘管理、列表优化等大多只支持 iOS/Android） | 中 | 每个依赖先过 §7 的"依赖准入矩阵"；桌面端回退到官方组件 + JS 实现 |
| **R6** | 长列表 + 富文本 + 图片在桌面端性能表现未经检验 | 中 | M2 结束前做 1k 条时间线滚动压测，三端记录 FPS |
| **R7** | `react-native-webview` 在 macOS 的支持与"离屏常驻 + 页面内 fetch"模式的稳定性未实测。两个隐含假设同样待证：① WKWebView 脱离视图树/0×0 时 JS 可能被挂起，"离屏常驻"可能需 1×1 透明常驻视图等技巧；② 上传接口在跨域域名，页面内 fetch 可能撞 CORS | 高（路线 B 地基） | M0 首个 spike 三端验证，**四项判据全过才算通过**：① 隐藏 WebView 加载 weibo.com → 注入 fetch → 取回 JSON；② 隐藏态、前后台切换、锁屏恢复后通道仍可用；③ 页面内 POST 能读取并附带 `X-XSRF-TOKEN`；④ 上传端点跨域行为实测。任一失败即触发方案评审：回退"原生 Cookie 桥 + 直连 HTTP"、上传改走可见 WebView，或收缩桌面端 |

> 注：R5 已随 Windows 平台移除，编号有意不回排，以保持 R6/R7 在下文的引用稳定。

**开工前核对：**

- [ ] 项目定位确认：个人学习/开源演示，GitHub 分发，不上架、不商用、不批量抓取
- [ ] 已通读微博用户协议相关条款，README 免责声明文案备好
- [ ] 个人微博账号 Web 端扫码登录正常，作为开发验证账号
- [ ] `react-native-webview` 离屏代理 spike 三端通过，覆盖 R7 全部四项判据（含隐藏常驻与上传跨域）（M0 首项）
- [ ] 已盘点开发机：Mac（Xcode ≥ 15）× 1（同时覆盖 iOS/macOS 开发）、iOS/Android 真机各 1
- [ ] 已通过 spike 锁定 RN core 与 RN macOS 对齐的版本号，记录到 `docs/VERSIONS.md`

---

## 4. 环境搭建 Checklist

### 4.1 通用

- [ ] Node LTS（与 RN CLI 要求匹配）+ Corepack/Yarn
- [ ] React Native DevTools / `npx react-native doctor` 全绿
- [ ] Git 仓库初始化 + `.gitignore`（三平台构建产物）
- [ ] 编辑器配置：TS、ESLint、Prettier 统一

### 4.2 iOS

- [ ] Xcode + Command Line Tools + CocoaPods + Watchman
- [ ] 模拟器运行 Hello World 成功
- [ ] 真机签名（开发者账号）配置完成

### 4.3 Android

- [ ] Android Studio：SDK 平台、Build-Tools、NDK（按 RN 要求）、`ANDROID_HOME`
- [ ] JDK 版本与 AGP 匹配
- [ ] 模拟器 + 真机（`adb`）运行 Hello World 成功

### 4.4 macOS（react-native-macos）

- [ ] 按 [RN macOS Getting Started](https://github.com/microsoft/react-native-macos/wiki/Intro-vs-%22*-native%22-projects) 初始化 macos 目录（`npx react-native-macos-init`）
- [ ] `pod install`（macos 目录）成功
- [ ] Xcode 运行 `MyWeiboApp (macOS)` Scheme 成功，窗口可缩放
- [ ] 确认 debug 端口（8081 metro）与 iOS 共存方式

---

## 5. 架构基线 Checklist（M0 出口条件）
- [ ] `npx @react-native-community/cli init` 生成基础工程，三平台壳工程全部可启动
- [ ] `package.json` scripts：`start` / `ios` / `android` / `macos` 一键可用
- [ ] `index.js` 中 `AppRegistry.runApplication` 对桌面 target（`macos` appKey）注册正确，三端渲染同一 `<App/>`
- [ ] TypeScript 严格模式 + 路径别名 `src/*`
- [ ] 平台扩展机制验证：一个示例组件在 4 端分别渲染不同文案，确认解析顺序
- [ ] 主题系统：light/dark 三端跟随系统；桌面端窗口宽度断点（<600 单栏、600–1000 双栏、>1000 三栏）
- [ ] 数据通道层：`WebViewChannel`（常驻离屏 WebView + 页面内 `fetch`，请求 ID ↔ 回包关联）+ 超时/重试/统一错误模型 + **全局限流器**（间隔 ≥1s、并发 ≤2）
- [ ] 风控降级链路：识别 punish/验证码响应 → 唤起可见 WebView 人工验证 → 自动重放失败请求
- [ ] 存储层封装：KV（`@react-native-async-storage/async-storage`，三端可用），仅存偏好/草稿/搜索历史；**登录凭证一律不落 App 存储**（Cookie 只存在于系统 WebView CookieJar）
- [ ] 日志与崩溃上报占位（Sentry 三端支持情况需 spike 验证）
- [ ] 导航容器：移动端 Bottom Tabs，桌面端 Side Nav（同一 Route 定义复用）
- [ ] ESLint + Prettier + Husky（pre-commit）+ `jest` 空跑通
- [ ] `docs/ARCHITECTURE.md` 记录 D1–D9 决策与理由

---

## 6. 功能里程碑

### M1 · 登录与会话（约 1 周）

依赖：M0 的 WebView spike（R7）通过。

- [ ] `WebViewChannel` 基座：常驻离屏 WebView（保持 weibo.com 源）、页面内 fetch 封装、请求 ID ↔ 回包关联、并发队列；隐藏态/前后台切换/锁屏恢复存活测试通过（R7 判据②）
- [ ] 登录窗口：内嵌 WebView 打开微博**扫码登录页**，用户人工完成（含滑块/短信验证），App 全程不接触账密
- [ ] 会话检测：轻量端点探测登录态；过期自动唤起重新登录
- [ ] "当前账号"全局状态（页面内 GET 自己的 profile → Zustand store）
- [ ] 退出登录：登出 + 清理 WebView 会话/Cookie（macOS 按平台 API 处理）
- [ ] 重启后会话恢复验证（依赖系统 CookieJar 持久化，三端各自实测）
- [ ] DoD：三端均可扫码登录 → 重启保持会话 → 登出后需重新登录

### M2 · 时间线（约 2 周）

- [ ] 数据层：关注时间线 Web 端点封装（weibo.com ajax 为主、m.weibo.cn container 兜底，端点以实测为准并全部收敛在 `src/api/web/`）+ 未登录空态
- [ ] 节流与缓存落地：全局限流生效、TanStack Query staleTime + 本地缓存（**降低风控触发概率优先于数据新鲜度**）
- [ ] 微博 Cell 组件：头像、昵称、认证标识、时间（相对时间）、来源、正文（含 @/话题/链接富文本渲染）、配图九宫格
- [ ] 下拉刷新 + 无限滚动分页（游标参数以 Web 端点实测为准）
- [ ] 图片加载 spike：`wx*.sinaimg.cn` 是否需要伪造 Referer、RN `Image` headers 在三端的支持实测（与 §7 图片库验证合并）
- [ ] 图片查看器（全屏、缩放、翻页）——平台兼容矩阵验证后选型
- [ ] 视频卡片（内联预览 + 点击进入播放；播放器三端支持是难点，允许 M2 降级为外链播放）
- [ ] 长列表性能：滚动 1k 条记录三端帧率，优化到 ≥ 50fps
- [ ] 骨架屏与空态/错误态
- [ ] DoD：三端流畅刷微博，转发微博与图片时间线渲染正确

### M3 · 发布微博（约 1.5 周）

- [ ] 发布编辑器：正文输入（140/长文提示）、计数
- [ ] 图片选择与多选上传（相册权限：iOS/Android；macOS 用 NSOpenPanel 桥接——平台扩展文件实现）
- [ ] 话题 #xx# 插入、@ 好友（可选 P1）
- [ ] 发送走页面内 POST：`X-XSRF-TOKEN` 由页面脚本读取后附带（可读性以 M0 spike R7 判据③实证为准，非天然保证）；失败预案 = 上传/发布改走可见 WebView 内完成
- [ ] 发送中状态、失败重试、草稿本地保存
- [ ] 发布成功后时间线插入新条目
- [ ] DoD：三端能发纯文本 + 带图微博并立即可见

### M4 · 详情与互动（约 2 周）

- [ ] 微博详情页：原文全文、话题链接、来源、发布时间绝对值
- [ ] 评论列表（分页）+ 发评论 + 评论回复楼
- [ ] 转发（直接转发 + 带意见转发）
- [ ] 点赞/取消点赞（乐观更新）
- [ ] 长按/右键操作菜单（**桌面端为鼠标右键 ContextMenu**，用扩展文件实现）
- [ ] 收藏（若 API 可得，否则记 P2）
- [ ] DoD：从时间线进入详情，完成一次"评论 + 转发 + 点赞"闭环

### M5 · 用户主页与关注（约 1.5 周）

- [ ] 个人主页：资料卡（头像/简介/粉丝/关注数/微博数）、微博列表、更多列表（图片/视频 tab）
- [ ] 关注 / 取关（乐观更新 + 回滚）
- [ ] 我的主页 + 编辑资料入口（P1）
- [ ] 他人主页的重定向（短链 `weibo.cn` 解析，P1）
- [ ] DoD：从任意微博可跳到作者主页并关注/取关

### M6 · 搜索与热搜（约 1.5 周）

- [ ] 搜索页：微博/用户/话题 三个 tab（Web 端搜索能力完整，直接全量落地，无开放平台权限之困）
- [ ] 热搜榜（Web 端侧边热搜数据）+ 点击进搜索结果
- [ ] 搜索历史（本地存储）、防抖请求、竞态取消
- [ ] 桌面端搜索快捷键（⌘K）
- [ ] DoD：三端可搜索并分页展示结果

### M7 · 消息中心（约 1.5 周，P1）

- [ ] 三类通知列表：@我、评论、转发（未读角标）
- [ ] 点击进入对应微博并高亮锚点
- [ ] 私信：Web 聊天接口实现成本高且敏感 → 首版仍降级为"跳网页版"，P2 再评估
- [ ] 下拉刷新 + 轮询未读数（App 前台时）
- [ ] DoD：收到 @ 与评论后消息页可见，跳转正确

### M8 · 桌面端专项打磨（macOS，约 1.5 周，与 M6/M7 部分并行）

- [ ] macOS 菜单栏（Menu）：常用动作（发微博、刷新、搜索）绑定应用菜单
- [ ] 键盘快捷键体系：`⌘R` 刷新、`⌘,` 设置、`Esc` 返回、`J/K` 上下切换微博（可选）
- [ ] 鼠标交互：hover 态、滚轮滚动、右键菜单、文本可选可复制
- [ ] 多栏布局：左导航 + 中列表 + 右详情（主从视图），窗口缩放自适应
- [ ] 窗口最小尺寸与多窗口行为验证
- [ ] 设置页：主题、字号、网络图片策略、清缓存
- [ ] DoD：macOS 桌面端达到"愿意日常使用"的基本体验，截图评审通过

### M9 · 质量与发布（约 2 周）

- [ ] 执行 §8.1 测试、§8.2 CI/CD、§8.3 发布通道全部条目，DoD 见 §9

---

## 7. 依赖准入矩阵（引入任何三方库前填一行）

| 库 | iOS | Android | macOS | 结论/回退 |
|---|---|---|---|---|
| react-native (core) | ✅ | ✅ | — | 基准版本锁 `docs/VERSIONS.md` |
| react-native-macos | — | — | ✅ | 与 core 同 minor |
| @react-navigation/native + elements(JS) | ⚠️ | ⚠️ | ⚠️ | JS 实现预期三端可用，M0 spike 随工程验证（未实测不标 ✅） |
| @react-native-async-storage/async-storage | ✅ | ✅ | ✅ | 官方支持 |
| zustand / @tanstack/query | ✅ | ✅ | ✅ | 纯 JS |
| react-native-keychain | ⚠️ | ⚠️ | ⚠️ | 路线 B 下基本不再需要（凭证留在 WebView CookieJar）；仅当要存其他敏感信息时重新评估 |
| expo-image / fast-image | ⚠️ | ⚠️ | ⚠️ | spike 验证（与 M2 图片加载/Referer 实测合并），失败则 RN `Image` + 手动缓存 |
| react-native-gesture-handler | ⚠️ | ⚠️ | ⚠️ | 移动端图片查看器可用；macOS 支持随 M0 spike 实测，失败则回退 JS PanResponder |
| react-native-webview | ✅ | ✅ | ⚠️ | **路线 B 核心依赖**（登录 + API 通道）；macOS 稳定性为 M0 首要 spike（R7） |
|（新库按需追加）| | | | |

- [ ] 每行状态在 M0 spike 中实测更新，不允许"未验证直接引入"
- [ ] 所有 ⚠️/❌ 项都有接口抽象 + 桌面回退实现

---

## 8. 测试与 CI/CD Checklist

### 8.1 测试

- [ ] 单元测试：API 层、stores、utils（目标行覆盖 ≥ 70%）
- [ ] 组件测试：`@testing-library/react-native` 覆盖核心 Cell/详情页
- [ ] Mock：以 `WebViewChannel` 为注入边界做 fake（回放 Web 端点契约 JSON），三端共用，UI 测试不依赖真微博
- [ ] 契约快照测试：关键端点响应留快照，微博改字段第一时间发现
- [ ] 节流器单测：限流、退避、请求去重
- [ ] E2E（P1）： Maestro 覆盖移动端登录→刷→发主链路
- [ ] 手工回归矩阵：3 平台 × 6 关键流程，每次发版执行
- [ ] 桌面专项：窗口缩放、键盘全操作可达性走查

### 8.2 CI/CD（GitHub Actions 矩阵）

- [ ] PR 门禁：lint + typecheck + 单测
- [ ] `ios.yml`：pod install + 模拟器构建（fastlane）
- [ ] `android.yml`：assembleDebug/Release（APK + AAB）
- [ ] `macos.yml`：runner 上 Xcode 构建 .app，签名后打包（可选 notarization）
- [ ] 版本与 Changelog 自动化（semantic-release 或手动 tag）
- [ ] 制品归档：三平台产物统一落到 Release 页

### 8.3 发布通道

- [ ] iOS：本机自签分发（Xcode 签名，免费账号 7 天重签 / 付费账号更久），README 附编译步骤。**不用 TestFlight**——其外测需过 App Store Connect Beta 审核，与 §1.1"不上架"及 R1 低调姿态冲突；仅限直连设备安装
- [ ] Android：apk 直发 / GitHub Releases；（若上架国内商店需另行合规评估）
- [ ] macOS：直接分发 .dmg（本地签名）+ notarization

---

## 9. 验收标准（整体 DoD）

- [ ] 三个平台首版安装包均可在干净环境（CI 产物）安装运行
- [ ] M1–M5 全部 P0 功能三端走查通过，截图/录屏留档到 `docs/reviews/`
- [ ] 冷启动：移动端 < 2s、桌面端 < 3s（基准设备）
- [ ] 时间线滚动 ≥ 50fps（中端手机 + M 系列 Mac）
- [ ] 崩溃率：内部测试期无阻断性崩溃；离线/弱网有明确降级 UI
- [ ] 登录凭证仅存于系统 WebView CookieJar；App 自有存储与日志中无任何 Cookie/凭证（三端验证）
- [ ] README 显著位置含免责声明与使用限制（个人学习用途、低频访问、尊重服务器），与 R1 缓解措施一致
- [ ] `README.md` 含三端从零跑起来的一句话命令；`docs/ARCHITECTURE.md`、`docs/VERSIONS.md` 与实现一致
- [ ] 已知限制清单（如私信降级、部分接口权限）在 README 显著位置声明

---

## 10. 里程碑排期（1–2 人）

| 阶段 | 内容 | 工期 | 出口条件 |
|---|---|---|---|
| M0 | 环境与架构基线（§4、§5、§7 spike） | 1.5 周 | 三端 Hello World + 版本锁定 + 依赖矩阵 + **R7 四项判据全过** |
| M1 | 登录与会话（WebViewChannel 基座） | 1 周 | 三端扫码登录 + 通道基座稳定 |
| M2 | 时间线 | 2 周 | 三端刷微博 + 性能达标 |
| M3 | 发布微博 | 1.5 周 | 三端发文闭环 |
| M4 | 详情与互动 | 2 周 | 评论/转发/点赞闭环 |
| M5 | 主页与关注 | 1.5 周 | 关注闭环 |
| M6 | 搜索与热搜 | 1.5 周 | 三 tab 搜索 + 热搜可用 |
| M7 | 消息中心 | 1.5 周 | 通知列表可用 |
| M8 | 桌面打磨（macOS） | 1.5 周（可与 M6/7 并行） | 桌面体验走查通过 |
| M9 | 测试收尾、CI/CD、三端发布 | 2 周 | §9 全部通过 |
| **合计** | | **串行之和 16.5 周；M8 与 M6/7 并行后关键路径约 12–14.5 周** | |

> 关键路径：M0 的 **WebViewChannel 三端 spike（R7）** 与 RN 版本对齐 spike（R3）——开放平台权限不再是阻塞项，但 R7 是路线 B 的地基，失败即触发方案评审（回退原生 Cookie 桥或收缩桌面端）。任一 spike 失败应在 M0 结束时定案，不带病进入 M1。

---

## 11. 参考资料

- React Native 文档：<https://reactnative.dev/docs/getting-started>
- microsoft/react-native-macos Releases：<https://github.com/microsoft/react-native-macos/releases>
- 微博开放平台文档（备用通道参考）：<https://open.weibo.com/wiki/Mainpage>
- Web 接口现状参考：[weibo-crawler（432 风控实例）](https://github.com/dataabc/weibo-crawler/issues/565)、[weibo-api-sdk（m 站免登录封装）](https://github.com/shibing624/weibo-api-sdk)、[RSSWorker 微博订阅生成器](https://github.com/yllhwa/RSSWorker)
