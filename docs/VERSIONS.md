# 版本基线（PLAN §3 前置核对最后一项）

> 本文件是"这套代码在什么环境上被证实可用"的唯一记录。**实测日期：2026-08-29**。
> 每次工具链/设备变化都要更新对应行，并在 commit message 里注明 `docs: 版本基线更新`。

## 宿主与工具链

| 项 | 值 | 来源 / 校验命令 |
|---|---|---|
| macOS | **26.6.2 (25G83)**，arm64 | `sw_vers` |
| Xcode | **26.6 (17F113)** | `xcodebuild -version` |
| Active developer dir | `/Applications/Xcode.app/Contents/Developer` | `xcode-select -p` |
| Command Line Tools | 26.6.0.0.1781586589 | `pkgutil --pkg-info=com.apple.pkg.CLTools_Executables` |
| Swift 编译器 | **6.3.3**（swiftlang-6.3.3.1.3 / clang-2100.1.1.101） | `swift --version` |
| Swift 语言模式 | **6**（`project.yml` 里 `SWIFT_VERSION: "6.0"`，严格并发） | `xcodebuild -showBuildSettings` |
| SwiftPM | 6.3.3（依赖约束只写进 `project.yml`，见 §依赖） | `swift package --version` |
| iPhoneOS SDK | **26.5**（`iphoneos26.5` / `iphonesimulator26.5`） | `xcodebuild -showsdks` |
| 部署目标 | **iOS 26.0**（PLAN §1：最低 iOS 26，iPhone 11/SE2 起） | `project.yml` |
| 模拟器 runtime | iOS **26.1 (23B86)** 与 **26.5 (23F77)** | `xcrun simctl list runtimes` |
| XcodeGen | 2.46.0 | `xcodegen --version` |
| SwiftLint | 0.65.1 | `swiftlint version` |
| SwiftFormat | 0.62.1 | `swiftformat --version` |
| Git | 2.50.1 (Apple Git-155) | `git --version` |

> PLAN §4.1 原文写"Xcode 26（Swift 6.2）"。实测环境已推进到 Xcode 26.6 / Swift 6.3.3；
> 语言模式仍按 Swift 6 严格并发跑，因此 §5 出口条件不受影响。**PLAN 尚未按实测口径修订**
> （D1 / §3 / §4.1 三处仍写 6.2），差异见下表，待以 `docs: 计划修订 v7——工具链口径按实测` 落实。

## 真机

| 项 | 值 |
|---|---|
| 机型 | **iPhone 15 Pro Max**（`iPhone16,2`，arm64e，256GB） |
| 系统 | **iOS 26.6.1 (23G83)** |
| 开发者模式 | enabled（`xcrun devicectl list devices` → `developerModeStatus`） |
| 配对 | paired，可无线调试（`coredevice.local`） |
| 真机冒烟 | ✅ 2026-08-29 调试态安装运行通过（Hello World 级） |
| 构建链验证 | ✅ `project.yml → xcodegen generate → xcodebuild`（iOS 26.5 模拟器）通过，SwiftUI + Liquid Glass API 编译无误 |

### ⚠️ 性能基线尚未成立（R6 / §9）

PLAN 的最低支持机型是 **iPhone 11 / SE2**，而当前唯一真机是 iPhone 15 Pro Max。
在它上面测出的"1k 条滚动 ≥50fps""冷启动 <2s"**不能作为 §9 的验收证据**——A17 Pro 的余量会掩盖
SwiftUI 长列表的解码抖动（R6 正是这个风险）。§8.1 的"机型矩阵：最新款 + 一代老款"目前**只有最新款**。

处理方式二选一（M2 前定案，不要拖到 M9）：
1. 补一台二手 iPhone 11 / SE2 作为性能基准机（推荐，几百块买断 R6）；
2. 显式改 PLAN 的验收口径：以 15 Pro Max 为基准，老机型走查降为 P1。

## 签名与分发（§8.3）

| 项 | 值 |
|---|---|
| 账号类型 | **免费 Personal Team**（`isFreeProvisioningTeam = 1`） |
| Team ID | `RZQCB7PHGD`（写死在 `project.yml`，fork 请改） |
| 签名身份 | `Apple Development: richeir@outlook.com (KQXFC96RQ9)` |
| 描述文件 | 自动管理，2 个（app + 单测 host） |
| **过期时间** | **2026-09-05**（真机包 7 天失效，届时重连 Xcode 重签） |
| 设备配额 | 免费 Team 每年可注册设备数极少，当前已占 1 台 |
| App ID 配额 | 已占 2（`dev.zhiwei.app`、`dev.zhiwei.app.tests`） |

→ PLAN §8.3 的判断成立：**当主力机演示建议升付费账号**（≥1 年有效期）。当前阶段用免费账号推进 M0/M1。

## 依赖

版本约束**只写在 `project.yml` 的 `packages:`**（生成的 `*.xcodeproj` 不入库，其内 `Package.resolved` 随之失效——PLAN §5 的原话）。

| 依赖 | 约束 | 状态 |
|---|---|---|
| [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | `from: 1.18.0` | 已接入（仅测试目标） |
| [Kingfisher](https://github.com/onevcat/Kingfisher) | `from: 8.6.0`（注释中） | **未启用**：M2 与 `sinaimg.cn` Referer 实测一起定 |
| [sentry-cocoa](https://github.com/getsentry/sentry-cocoa) | `from: 8.40.0`（注释中） | **未启用**：§5 只要求占位，当前用 `NoopCrashReporter` |
| CocoaPods | — | 无残留（无 `Podfile`，`pod install` 不在任何脚本里） |

## PLAN 差异（本次环境实测得到的修订）

| 位置 | 原文 | 修订 |
|---|---|---|
| §3 前置核对 / §4.1 | "Mac（Xcode ≥ 26，Swift 6.2）" | Xcode ≥ 26（**实测 26.6 / Swift 6.3.3**，语言模式 6） |
| §4.1 | "SwiftLint + SwiftFormat 配置并接入 pre-commit" | 落点明确为 **`.githooks/pre-commit` + `core.hooksPath`**（零新依赖，不引 python 版 pre-commit） |
| §8.1 / §9 性能基线 | "机型矩阵：最新款 + 一代老款" | 老款机缺失，已在本文标 ⚠️，M2 前定案 |
