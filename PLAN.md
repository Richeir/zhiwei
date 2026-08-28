# 新浪微博客户端（React Native 四平台）项目计划

> 目标：用 React Native 构建一个微博客户端，代码绝大部分共享，一套仓库同时产出 **iOS / Android / macOS / Windows** 四个平台的应用。
>
> 文档状态：v1 · 待评审
> 交付物约定：每个里程碑（Mx）都有验收标准（DoD）与可勾选的任务清单。

---

## 1. 项目概述

| 项 | 内容 |
|---|---|
| 产品形态 | 新浪微博第三方客户端（移动端 + 桌面端） |
| 技术栈 | React Native（Bare）+ react-native-windows + react-native-macos |
| 平台 | iOS、Android、macOS、Windows 10/11 |
| 数据来源 | 微博开放平台 API（OAuth 2.0），受限接口见 §3 风险 |
| 团队假设 | 1–2 名开发，全栈 RN |
| 总工期估算 | 约 14–18 周（详见 §10） |

### 1.1 产品目标（P0 = 首版必须，P1 = 首版尽量，P2 = 后续迭代）

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
| D1 | 脚手架 | **Bare React Native CLI**（`@react-native-community/cli`），不用 Expo | Expo 官方 SDK 不覆盖 `react-native-windows` / `react-native-macos` 目标；Bare 模式对四平台 target 控制最完整 |
| D2 | 桌面端框架 | [react-native-windows](https://github.com/microsoft/react-native-windows/releases)（WinUI 3）+ [react-native-macos](https://github.com/microsoft/react-native-macos/releases) | 微软官方维护的 RN 平台扩展，与 RN core 同 minor 版本对齐发布（当前 RNW 已到 [v0.81+](https://devblogs.microsoft.com/react-native/react-native-windows-v0-81-is-here/)） |
| D3 | 多平台组织 | 单仓单 App + **平台扩展文件**（`.ios.tsx` / `.android.tsx` / `.macos.tsx` / `.windows.tsx` / `.native.tsx`） | 简单直接；共享逻辑放 `src/`，平台壳工程各自独立 |
| D4 | 新架构（Fabric/TurboModules） | 首版按 RNW/RN macOS 当前稳定支持情况决定，默认**先跑通旧架构兼容路径，新架构作为 spike** | 见 §3 R3；两桌面框架对 New Architecture 的支持节奏与 core 不同步 |
| D5 | 导航 | React Navigation（JS Stack + Tabs），桌面端切换为**侧边栏导航**布局 | `react-native-screens`/native-stack 在 Windows 不可用，统一用 JS 实现保证四端一致 |
| D6 | 状态与数据 | Zustand（UI 状态）+ TanStack Query（服务端数据）+ Axios | 轻量、纯 JS、无原生依赖，天然四平台兼容 |
| D7 | UI 组件 | 自建薄组件层 + React Native Paper（可选主题层） | 避免依赖只支持手机端的组件库；桌面差异用扩展文件处理 |
| D8 | 语言 | TypeScript 全覆盖 | — |

### 2.2 仓库结构（规划）

```
my-weibo-app/
├── index.js                    # 单一入口，注册 AppRegistry（含 Desktop_app 注册）
├── package.json                # 依赖四平台框架与 scripts（ios/android/macos/windows）
├── ios/                        # RN iOS 工程（CocoaPods）
├── android/                    # RN Android 工程（Gradle）
├── macos/                      # react-native-macos 工程（Xcode + CocoaPods）
├── windows/                    # react-native-windows 工程（VS2022 + MSBuild）
│   └── MyWeiboApp/
├── src/
│   ├── app/                    # App 组装：导航容器、主题、Provider
│   ├── features/               # 按功能域切分
│   │   ├── auth/               # 登录、OAuth 回调、token 管理
│   │   ├── timeline/           # 关注/推荐时间线
│   │   ├── compose/            # 发布微博（文字/图片/话题/位置）
│   │   ├── detail/             # 微博详情、评论、转发、点赞
│   │   ├── profile/            # 用户主页、关注列表
│   │   ├── search/             # 搜索、热搜
│   │   └── notifications/      # 消息中心
│   ├── api/                    # 微博 API 客户端、DTO、签名/授权拦截器
│   ├── components/             # 共享 UI 组件（Cell、Avatar、RichText…）
│   │   └── *.windows.tsx       # 平台差异用扩展文件覆盖
│   ├── desktop/                # 桌面专属：菜单栏、快捷键、多栏布局
│   ├── stores/  hooks/  utils/  assets/  theme/
└── __tests__/  scripts/  docs/
```

---

## 3. 风险与前置条件（开工前必读）

| # | 风险 | 影响 | 缓解措施 |
|---|---|---|---|
| **R1** | **微博开放平台 API 权限收紧**：多数时间线/搜索接口需要应用审核与接口权限申请，个人开发者可申请的权限非常有限（参考 [微博开放平台](https://open.weibo.com/wiki/Mainpage)） | 高：可能拿不到 `statuses/home_timeline`、`search/topics` 等 | ① 立项第一周就提交应用注册 + 权限申请；② 用自有的"测试用户"账号验证全链路；③ 设计 API 抽象层，允许后续替换数据源；④ 明确不做爬虫方案（合规风险），若 API 不可得则调整为"演示版"范围 |
| **R2** | OAuth 回调需要 https 域名 / App Link | 中 | 准备一个自有域名的回调页（静态托管即可）；移动端用 `react-native-navigation` deep link / App AuthSession |
| **R3** | 新架构（0.76+ Fabric 默认）与 RNW / RN macOS 的支持节奏不完全同步，部分三方库未适配 | 中 | M0 阶段做一次**四平台空工程 spike**，锁定一个四端全对齐的 RN minor 版本再大规模开发 |
| **R4** | 三方库平台覆盖不全（图片库、secure storage、键盘管理、列表优化等大多只支持 iOS/Android） | 中 | 每个依赖先过 §7 的"依赖准入矩阵"；桌面端回退到官方组件 + JS 实现 |
| **R5** | Windows 端开发必须 Windows 环境（VS2022 C++ 工作负载），macOS 端需要能跑 Xcode 的机器 | 中 | 团队机器盘点；CI 矩阵补位（见 §8） |
| **R6** | 长列表 + 富文本 + 图片在桌面端性能表现未经检验 | 中 | M2 结束前做 1k 条时间线滚动压测，四端记录 FPS |
| **R7** | 微博内容合规（展示第三方内容上线应用商店） | 低–中 | 首版定位个人/开源项目分发，不上架中国区商店；上线前复查商店与开放平台条款 |

**开工前核对：**

- [ ] 已注册微博开放平台开发者账号，创建应用拿到 `App Key / App Secret`
- [ ] 已确认目标 App 可申请的接口清单（登录、时间线、发布、评论、点赞、关注、搜索）
- [ ] 已准备 OAuth 回调域名/页面
- [ ] 已盘点开发机：Mac（Xcode ≥ 15）× 1、Windows 11（VS2022）× 1、iOS/Android 真机各 1
- [ ] 已通过 spike 锁定 RN core / RNW / RN macOS 三者对齐的版本号，记录到 `docs/VERSIONS.md`

---

## 4. 环境搭建 Checklist

### 4.1 通用

- [ ] Node LTS（与 RN CLI 要求匹配）+ Corepack/Yarn
- [ ] React Native DevTools / `npx react-native doctor` 全绿
- [ ] Git 仓库初始化 + `.gitignore`（四平台构建产物）
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

### 4.5 Windows（react-native-windows）

- [ ] VS2022：`.NET 桌面开发` + `C++ 桌面开发` + `Windows 10/11 SDK` + `MSIX 打包负载`
- [ ] Node 工具链 + `npx react-native-windows-init`（目标 RN 版本与 D4 决策一致）
- [ ] `npx react-native run-windows` 首次构建通过（注意首次需较长编译时间，建议 Release/Debug 各验证一次）
- [ ] Windows App SDK / WinUI 运行时部署确认

---

## 5. 架构基线 Checklist（M0 出口条件）

- [ ] `npx @react-native-community/cli init` 生成基础工程，四平台壳工程全部可启动
- [ ] `package.json` scripts：`start` / `ios` / `android` / `macos` / `windows` 一键可用
- [ ] `index.js` 中 `AppRegistry.runApplication` 对桌面 target（`macos`/`windows` appKey）注册正确，四端渲染同一 `<App/>`
- [ ] TypeScript 严格模式 + 路径别名 `src/*`
- [ ] 平台扩展机制验证：一个示例组件在 4 端分别渲染不同文案，确认解析顺序
- [ ] 主题系统：light/dark 四端跟随系统；桌面端窗口宽度断点（<600 单栏、600–1000 双栏、>1000 三栏）
- [ ] 网络层：Axios 实例 + token 拦截器 + 统一错误模型 + 请求重试
- [ ] 存储层封装：KV（`@react-native-async-storage/async-storage`，四端可用）；安全存储接口 `SecureTokenStore`（iOS/Android/macOS 用 Keychain 系方案，Windows 用 CredentialLocker，接口统一、平台实现分离）
- [ ] 日志与崩溃上报占位（Sentry 四端支持情况需 spike 验证）
- [ ] 导航容器：移动端 Bottom Tabs，桌面端 Side Nav（同一 Route 定义复用）
- [ ] ESLint + Prettier + Husky（pre-commit）+ `jest` 空跑通
- [ ] `docs/ARCHITECTURE.md` 记录 D1–D8 决策与理由

---

## 6. 功能里程碑

### M1 · 登录与账号（约 1.5 周）

依赖：R1/R2 前置项完成。

- [ ] OAuth 2.0 授权流程：`useAuthSession`（或 Linking 打开系统浏览器）→ 回调 → 换 `access_token`
- [ ] Token 持久化 + 过期刷新（refresh_token）+ 失效重登
- [ ] 登录页 UI（移动端全屏 / 桌面端居中卡片），四端走查
- [ ] "以 XX 身份登录"的全局账号状态（Zustand store）
- [ ] 退出登录、清除凭证
- [ ] 深链接回调在四端分别验证（含 Windows URL 协议注册）
- [ ] DoD：四端均可完成登录 → 重启 App 保持会话 → 登出

### M2 · 时间线（约 2 周）

- [ ] API 层：`statuses/friends_timeline`（关注）+ 未登录/降级数据源占位
- [ ] 微博 Cell 组件：头像、昵称、认证标识、时间（相对时间）、来源、正文（含 @/话题/链接富文本渲染）、配图九宫格
- [ ] 下拉刷新 + 无限滚动分页（`max_id` 游标）
- [ ] 图片查看器（全屏、缩放、翻页）——平台兼容矩阵验证后选型
- [ ] 视频卡片（内联预览 + 点击进入播放；播放器四端支持是难点，允许 M2 降级为外链播放）
- [ ] 长列表性能：滚动 1k 条记录四端帧率，优化到 ≥ 50fps
- [ ] 骨架屏与空态/错误态
- [ ] DoD：四端流畅刷微博，转发微博与图片时间线渲染正确

### M3 · 发布微博（约 1.5 周）

- [ ] 发布编辑器：正文输入（140/长文提示）、计数
- [ ] 图片选择与多选上传（相册权限：iOS/Android；macOS 用 NSOpenPanel 桥接、Windows 用 FileOpenPicker 桥接——平台扩展文件实现）
- [ ] 话题 #xx# 插入、@ 好友（可选 P1）
- [ ] 发送中状态、失败重试、草稿本地保存
- [ ] 发布成功后时间线插入新条目
- [ ] DoD：四端能发纯文本 + 带图微博并立即可见

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

- [ ] 搜索页：微博/用户/话题 三个 tab（受 R1 权限影响，至少落地本地可得的方案）
- [ ] 热搜榜（`common/get_hotflow` 或可得接口）+ 点击进搜索结果
- [ ] 搜索历史（本地存储）、防抖请求、竞态取消
- [ ] 桌面端搜索快捷键（⌘K / Ctrl+K）
- [ ] DoD：四端可搜索并分页展示结果

### M7 · 消息中心（约 1.5 周，P1）

- [ ] 三类通知列表：@我、评论、转发（未读角标）
- [ ] 点击进入对应微博并高亮锚点
- [ ] 私信：开放平台 API 已不开放 → **明确降级为"跳官方客户端/网页"**，避免踩线
- [ ] 下拉刷新 + 轮询未读数（App 前台时）
- [ ] DoD：收到 @ 与评论后消息页可见，跳转正确

### M8 · 桌面端专项打磨（约 2 周，与 M6/M7 部分并行）

- [ ] macOS 菜单栏（Menu）：常用动作（发微博、刷新、搜索）绑定应用菜单
- [ ] Windows 菜单/命令栏 + 标题栏区域适配
- [ ] 键盘快捷键体系：`⌘/Ctrl+R` 刷新、`⌘/Ctrl+,` 设置、`Esc` 返回、`J/K` 上下切换微博（可选）
- [ ] 鼠标交互：hover 态、滚轮滚动、右键菜单、文本可选可复制
- [ ] 多栏布局：左导航 + 中列表 + 右详情（主从视图），窗口缩放自适应
- [ ] 窗口最小尺寸与多窗口行为验证
- [ ] 设置页：主题、字号、网络图片策略、清缓存
- [ ] DoD：桌面两端达到"愿意日常使用"的基本体验，截图评审通过

### M9 · 质量与发布（约 2 周，见 §8/§9）

---

## 7. 依赖准入矩阵（引入任何三方库前填一行）

| 库 | iOS | Android | macOS | Windows | 结论/回退 |
|---|---|---|---|---|---|
| react-native (core) | ✅ | ✅ | — | — | 基准版本锁 `docs/VERSIONS.md` |
| react-native-macos | — | — | ✅ | — | 与 core 同 minor |
| react-native-windows | — | — | — | ✅ | 与 core 同 minor |
| @react-navigation/native + elements(JS) | ✅ | ✅ | ✅ | ✅ | 已验证四端纯 JS 可用 |
| @react-native-async-storage/async-storage | ✅ | ✅ | ✅ | ✅ | 官方支持 |
| zustand / @tanstack/query / axios | ✅ | ✅ | ✅ | ✅ | 纯 JS |
| react-native-keychain | ⚠️ 待验证 | ⚠️ | ⚠️ | ❌ | 抽象 `SecureTokenStore`；Windows 用 WinRT CredentialManager |
| expo-image / fast-image | ⚠️ | ⚠️ | ⚠️ | ⚠️ | spike 验证，失败则 RN `Image` + 手动缓存 |
| react-native-gesture-handler | ⚠️ | ⚠️ | ⚠️ | ❌/⚠️ | 移动端图片查看器可用；桌面端回退 JS PanResponder |
| react-native-webview | ✅ | ✅ | ⚠️ | ✅ | 登录 H5/富文本兜底；macOS 需验证 |
|（新库按需追加）| | | | | |

- [ ] 每行状态在 M0 spike 中实测更新，不允许"未验证直接引入"
- [ ] 所有 ⚠️/❌ 项都有接口抽象 + 桌面回退实现

---

## 8. 测试与 CI/CD Checklist

### 8.1 测试

- [ ] 单元测试：API 层、stores、utils（目标行覆盖 ≥ 70%）
- [ ] 组件测试：`@testing-library/react-native` 覆盖核心 Cell/详情页
- [ ] Mock：MSW（Mock Service Worker）模拟微博 API 契约，四端共用
- [ ] E2E（P1）： Maestro 覆盖移动端登录→刷→发主链路
- [ ] 手工回归矩阵：4 平台 × 6 关键流程，每次发版执行
- [ ] 桌面专项：窗口缩放、键盘全操作可达性走查

### 8.2 CI/CD（GitHub Actions 矩阵）

- [ ] PR 门禁：lint + typecheck + 单测
- [ ] `ios.yml`：pod install + 模拟器构建（fastlane）
- [ ] `android.yml`：assembleDebug/Release（APK + AAB）
- [ ] `macos.yml`：runner 上 Xcode 构建 .app，签名后打包（可选 notarization）
- [ ] `windows.yml`：VS2022 runner，MSBuild + MSIX 打包
- [ ] 版本与 Changelog 自动化（semantic-release 或手动 tag）
- [ ] 制品归档：四平台产物统一落到 Release 页

### 8.3 发布通道

- [ ] iOS：TestFlight（Apple 开发者账号）
- [ ] Android：apk 直发 / GitHub Releases；（若上架国内商店需另行合规评估）
- [ ] macOS：直接分发 .dmg（本地签名）+ notarization
- [ ] Windows：MSIX / GitHub Releases 安装包，代码签名证书（P1，可先无签名 + 使用说明）

---

## 9. 验收标准（整体 DoD）

- [ ] 四个平台首版安装包均可在干净环境（CI 产物）安装运行
- [ ] M1–M5 全部 P0 功能四端走查通过，截图/录屏留档到 `docs/reviews/`
- [ ] 冷启动：移动端 < 2s、桌面端 < 3s（基准设备）
- [ ] 时间线滚动 ≥ 50fps（中端设备 + Win11 笔记本 + M 系列 Mac）
- [ ] 崩溃率：内部测试期无阻断性崩溃；离线/弱网有明确降级 UI
- [ ] Token 等敏感信息不落地明文（四端验证）
- [ ] `README.md` 含四端从零跑起来的一句话命令；`docs/ARCHITECTURE.md`、`docs/VERSIONS.md` 与实现一致
- [ ] 已知限制清单（如私信降级、部分接口权限）在 README 显著位置声明

---

## 10. 里程碑排期（1–2 人）

| 阶段 | 内容 | 工期 | 出口条件 |
|---|---|---|---|
| M0 | 环境与架构基线（§4、§5、§7 spike） | 1.5 周 | 四端 Hello World + 版本锁定 + 依赖矩阵 |
| M1 | 登录与账号 | 1.5 周 | 四端登录闭环 |
| M2 | 时间线 | 2 周 | 四端刷微博 + 性能达标 |
| M3 | 发布微博 | 1.5 周 | 四端发文闭环 |
| M4 | 详情与互动 | 2 周 | 评论/转发/点赞闭环 |
| M5 | 主页与关注 | 1.5 周 | 关注闭环 |
| M6 | 搜索与热搜 | 1.5 周 | 搜索可用（视 R1 权限） |
| M7 | 消息中心 | 1.5 周 | 通知列表可用 |
| M8 | 桌面打磨 | 2 周（可与 M6/7 并行） | 桌面体验走查通过 |
| M9 | 测试收尾、CI/CD、四端发布 | 2 周 | §9 全部通过 |
| **合计** | | **约 15–18 周（并行后 ≈ 14 周）** | |

> 关键路径：M0 的 API 权限确认（R1）与版本对齐 spike（R3）。二者任一失败都应在 M0 结束时触发范围评审，而不是带病进入 M1。

---

## 11. 参考资料

- React Native 文档：<https://reactnative.dev/docs/getting-started>
- microsoft/react-native-windows Releases：<https://github.com/microsoft/react-native-windows/releases>
- RNW v0.81 发布说明：<https://devblogs.microsoft.com/react-native/react-native-windows-v0-81-is-here/>
- microsoft/react-native-macos Releases：<https://github.com/microsoft/react-native-macos/releases>
- 微博开放平台文档：<https://open.weibo.com/wiki/Mainpage>
