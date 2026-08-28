# AGENTS.md

## Project

iOS 新浪微博第三方客户端——Swift + SwiftUI，最低 iOS 26，个人学习/开源演示定位（不上架、不商用、不批量抓取）。

**先读 `PLAN.md`**：技术决策（D1–D9）、风险与判据（R1–R7）、里程碑与出口条件（§4–§10）全部以该文件为准。

硬约束（细节见 PLAN.md）：

- 工程由 XcodeGen `project.yml` 文本定义；`*.xcodeproj` 是生成产物，禁止入库或手改 pbxproj
- 微博 Web 端点定义全部收敛 `Core/APIWeb/`，Web 改版只动这一处
- 所有网络入口收敛 `WebViewChannel` 协议，任何库/请求不得绕行限流 actor（间隔 ≥1s、并发 ≤2）
- 登录凭证仅存系统 WebKit CookieJar，不落 App 自有存储与日志

## Conventions

- Read the relevant modules before making changes
- Keep consistent with the existing code style
- 修订 PLAN.md 时废弃编号不重排（D2/D3、R3–R5、M8），以保持交叉引用稳定；改动需同步相关 DoD 与风险判据，并以 `docs: 计划修订 vX——摘要` 形式提交
