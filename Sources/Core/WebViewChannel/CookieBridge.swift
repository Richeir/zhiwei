import Foundation
import WebKit

// MARK: - Cookie 桥（PLAN D9 质变点 a / R7 判据③）
//
// 原生语境下 `WKHTTPCookieStore.getAllCookies` **能读到 httpOnly** 的 `SUB` / `XSRF-TOKEN`，
// 这是相对 RN 路线的根本性差别（RN 里"页面脚本能否读到 httpOnly"是个未证假设）。
// 本文件只做搬运与判定，**任何函数都不得把 cookie 值写进日志**（红线，见 Core/Diagnostics）。
enum CookieBridge {
    /// WebKit 登录态相关的 cookie 名（只用于"存在性"判定，值不外传）
    static let loginCookieNames: Set<String> = ["SUB", "SUBP", "XSRF-TOKEN", "ALC", "SSOLoginState"]

    /// 取 WKWebView 的全部 cookie（含 httpOnly）。
    static func allCookies(from store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { (cont: CheckedContinuation<[HTTPCookie], Never>) in
            store.getAllCookies { cont.resume(returning: $0) }
        }
    }

    /// 我们关心的域（其余域的 cookie 不进原生车道，避免把无关站点凭证带出边界）
    static let weiboDomains: [String] = [".weibo.com", ".weibo.cn", ".sina.com.cn"]

    /// 把 WebKit 的 cookie 同步进 `HTTPCookieStorage.shared`，让原生车道② 自动携带。
    ///
    /// - Returns: 实际同步的条数（不返回内容）
    @discardableResult
    static func syncToSharedStorage(_ cookies: [HTTPCookie]) -> Int {
        let storage = HTTPCookieStorage.shared
        let keep = cookies.filter { cookie in
            weiboDomains.contains { domain in cookie.domain == domain || cookie.domain.hasSuffix(domain) }
        }

        // 先清掉上一次同步的同域条目，避免 WebKit 侧已失效的 cookie 在原生侧复活（R2 过期场景）
        let stale = (storage.cookies ?? []).filter { cookie in
            weiboDomains.contains { domain in cookie.domain == domain || cookie.domain.hasSuffix(domain) }
        }
        for cookie in stale where !keep.contains(where: { $0.name == cookie.name && $0.domain == cookie.domain }) {
            storage.deleteCookie(cookie)
        }
        for cookie in keep {
            storage.setCookie(cookie)
        }
        return keep.count
    }

    /// 是否观察到登录所需 cookie（只回答布尔，不外传值）——R7 判据③的判据点
    static func hasLoginCookies(_ cookies: [HTTPCookie]) -> Bool {
        let names = Set(cookies.map(\.name))
        return names.contains("SUB") || !loginCookieNames.isDisjoint(with: names)
    }

    /// 取 XSRF-TOKEN 用于写操作请求头。
    ///
    /// 注意：返回值只应进入**请求头**，不得进日志/存储；调用方负责不落盘。
    static func xsrfToken(in cookies: [HTTPCookie]) -> String? {
        cookies.first(where: { $0.name == "XSRF-TOKEN" })?.value
    }

    /// 登出：清空 WebKit 全部站点数据（PLAN M1「退出登录」条目）。
    ///
    /// 这是本项目里唯一允许"删凭证"的路径；App 自有存储从来就没有凭证可删。
    /// `@MainActor`：iOS 26 SDK 起 `WKWebsiteDataStore.default()` / `allWebsiteDataTypes()` 均为主 actor 隔离。
    @MainActor
    static func purgeAllBrowsingData() async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            store.removeData(ofTypes: types, modifiedSince: .distantPast) { cont.resume() }
        }
        // 原生侧同步残留一并清掉
        let shared = HTTPCookieStorage.shared
        for cookie in shared.cookies ?? [] where weiboDomains.contains { cookie.domain == $0 || cookie.domain.hasSuffix($0) } {
            shared.deleteCookie(cookie)
        }
    }
}
