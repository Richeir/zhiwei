import Foundation
import SwiftUI

// MARK: - 正文富文本（PLAN §2.2「自建薄组件层（Cell/Avatar/RichText）」、M2「@/话题/链接富文本，分段着色可点击」）
//
// 微博 Web 回包的正文是 HTML 片段：`<a href="/n/xxx">@昵称</a>`、`<a href="/search?q=%23话题%23">#话题#</a>`、
// `<br />`、各种实体。策略：**先剥成纯文本，再按语义正则重新分段**——
// 不去解析 Web 的 HTML 结构（那是改版时最脆的一环），只认稳定存在的文字模式。

enum StatusText {
    enum Segment: Equatable, Sendable {
        case plain(String)
        case mention(String)
        case topic(String)
        case link(title: String, url: URL)
    }

    /// 剥 HTML + 分段。`@MainActor`：`NSAttributedString(html:)` 限主线程。
    @MainActor
    static func segments(from html: String?) -> [Segment] {
        let text = HTMLText.strip(html)
        guard !text.isEmpty else { return [] }
        return split(text)
    }

    @MainActor
    static func attributedString(from html: String?, linkColor: Color = Theme.accent) -> AttributedString {
        var result = AttributedString()
        for segment in segments(from: html) {
            switch segment {
            case .plain(let value):
                result.append(AttributedString(value))
            case .mention(let name):
                var attributed = AttributedString("@\(name)")
                attributed.foregroundColor = linkColor
                attributed.link = URL(string: "zhiwei://user?name=\(name.percentEncoded)")
                result.append(attributed)
            case .topic(let name):
                var attributed = AttributedString("#\(name)#")
                attributed.foregroundColor = linkColor
                attributed.link = URL(string: "zhiwei://topic?name=\(name.percentEncoded)")
                result.append(attributed)
            case .link(let title, let url):
                var attributed = AttributedString(title)
                attributed.foregroundColor = linkColor
                attributed.link = url
                attributed.underlineStyle = .single
                result.append(attributed)
            }
        }
        return result
    }

    // MARK: 分段实现

    @MainActor
    private static func split(_ text: String) -> [Segment] {
        // 三种模式一次扫完：话题（#…#，允许带 (1) 计数后缀）、@提及、裸链
        let pattern = "#([^#\\n]{1,80})#|@([\\w\\p{Han}\\-_]{1,40})|(https?://[^\\s，。、）)]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [.plain(text)] }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        var segments: [Segment] = []
        var cursor = text.startIndex

        for match in regex.matches(in: text, range: range) {
            let whole = Range(match.range, in: text)!
            if whole.lowerBound > cursor {
                segments.append(.plain(String(text[cursor ..< whole.lowerBound])))
            }
            if let topic = matchedText(match, at: 1, in: text) {
                segments.append(.topic(topic.normalizedTopic))
            } else if let mention = matchedText(match, at: 2, in: text) {
                segments.append(.mention(mention))
            } else if let link = matchedText(match, at: 3, in: text), let url = URL(string: link) {
                segments.append(.link(title: link.shortenedLink, url: url))
            }
            cursor = whole.upperBound
        }
        if cursor < text.endIndex {
            segments.append(.plain(String(text[cursor...])))
        }
        return segments
    }

    /// NSRange（UTF-16）→ String 子串；越界或组未命中都返回 nil（不抛，正文解析不许让 Cell 崩）
    private static func matchedText(_ match: NSTextCheckingResult, at group: Int, in text: String) -> String? {
        let range = match.range(at: group)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }
}

private extension String {
    /// `话题(123)` → `话题`：Web 端给话题带热度计数后缀
    var normalizedTopic: String {
        guard let paren = firstIndex(of: "(") else { return trimmingCharacters(in: .whitespaces) }
        return String(prefix(upTo: paren)).trimmingCharacters(in: .whitespaces)
    }

    /// 长链接只显示域名 + 省略号（正文里全长度 URL 极占行）
    var shortenedLink: String {
        guard count > 28, let host = URL(string: self)?.host else { return self }
        return "\(host)/…"
    }

    var percentEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? self
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}

// MARK: 视图

/// 正文视图：整体一个 `Text(AttributedString)`，链接点击交给 `OpenURLAction` 转成 Route。
struct StatusTextView: View {
    let html: String?
    var onRoute: (Route) -> Void = { _ in }

    var body: some View {
        Text(StatusText.attributedString(from: html))
            .lineSpacing(Theme.bodyLineSpacing)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                switch url.scheme {
                case "zhiwei":
                    if url.host == "topic", let name = url.queryValue("name") {
                        onRoute(.topic(name: name))
                    }
                    return .handled
                default:
                    return .systemAction
                }
            })
    }
}

private extension URL {
    func queryValue(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }
}
