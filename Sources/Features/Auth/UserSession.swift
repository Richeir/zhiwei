import Foundation
import os

// MARK: - 当前账号全局状态（PLAN M1「`@Observable` UserSession」）
//
// M0 只定形态与状态迁移；扫码登录与自动重登在 M1 落地。
// 凭证红线：本对象**永远不持有 cookie/token**，只有"登录态 + 展示用的用户资料"。

@MainActor
@Observable
final class UserSession {
    enum Status: Sendable, Equatable {
        /// 未开始探测
        case unknown
        /// 正在探测（冷启动时短暂出现，避免闪一下登录页）
        case probing
        case signedIn(WBUser)
        case signedOut
        /// 需要人工验证（风控），登录与会话探测共用这一个入口
        case needsVerification(PunishChallenge)

        var isLoggedIn: Bool {
            if case .signedIn = self {
                true
            } else {
                false
            }
        }
    }

    private(set) var status: Status = .unknown
    /// 登录 sheet 的呈现意图（由通道/会话层置位，RootView 消费——避免 Feature 之间互相持有）
    var loginRequested = false
    /// 会话级缓存（时间线载荷等）：登出时逐个 `purge`，避免跨账号残留（R2）。
    var sessionScopedCaches: [any SessionScopedCache] = []

    func probe(using channel: any WebViewChannel) async {
        if case .probing = status {
            return
        }
        status = .probing
        do {
            let probe = try await Self.probeWithWarmup(channel)
            guard probe.isLoggedIn, let uid = probe.uid else {
                status = .signedOut
                loginRequested = true
                return
            }
            // M1：探测端点顺手带回的资料有限，这里先立占位，完整 profile 由主页请求补齐
            status = .signedIn(WBUser.stub(uid: uid))
            Logger.log(domain: .auth).info("session ok (cookies observed: \(probe.sawLoginCookies, privacy: .public))")
        } catch let error as APIError {
            switch error {
            case .punished(let challenge):
                status = .needsVerification(challenge)
            case .notLoggedIn, .httpStatus(401), .httpStatus(403):
                status = .signedOut
                loginRequested = true
            default:
                // 网络抖动不把已登录状态打回未登录（R2：误判会引发无谓的重新登录）
                if case .unknown = status {
                    status = .signedOut
                }
                Logger.log(domain: .auth).error("probe failed: \(String(describing: error), privacy: .public)")
            }
        } catch {
            Logger.log(domain: .auth).error("probe failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// 冷启动 WebKit 可能还没把磁盘 cookie 载入（`getAllCookies` 首次返回 0 条），
    /// 与「真未登录」区分：完全没读到登录 cookie 时短延迟重试，给存储预热时间。
    private static func probeWithWarmup(
        _ channel: any WebViewChannel, maxAttempts: Int = 4) async throws -> SessionProbe {
        var probe = try await channel.probeSession()
        var attempt = 1
        while !probe.isLoggedIn, !probe.sawLoginCookies, attempt < maxAttempts {
            try? await Task.sleep(for: .milliseconds(300 * attempt))
            probe = try await channel.probeSession()
            attempt += 1
        }
        return probe
    }

    /// 登出：清 WebKit 站点数据（凭证唯一居所）+ 会话级缓存，并回到未登录态（M1）
    func signOut() async {
        await CookieBridge.purgeAllBrowsingData()
        sessionScopedCaches.forEach { $0.purge() }
        status = .signedOut
        loginRequested = false
        Logger.log(domain: .auth).info("signed out")
    }
}

private extension WBUser {
    /// 探测阶段的最小可用资料（只有 uid 是确定的，其余留空由主页请求覆盖）
    static func stub(uid: String) -> WBUser {
        var user = WBUser.empty
        user.id = uid
        return user
    }
}

extension WBUser {
    /// 供 stub 与预览使用的空值构造
    static var empty: WBUser {
        WBUser(
            id: "",
            screenName: "",
            avatarURL: nil,
            verified: false,
            verifiedReason: nil,
            verifiedType: -1,
            followers: 0,
            follows: 0,
            statusCount: 0,
            bio: nil,
            isFollowing: nil,
            profileURL: nil)
    }
}
