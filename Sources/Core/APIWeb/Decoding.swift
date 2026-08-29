import Foundation

// MARK: - Web 端解码适配（PLAN §2.2「改版只动 `Core/APIWeb`」）
//
// 微博 Web 回包的三件脏活，全部消化在这一层，DTO 对外给出干净类型：
//   1. 数字常以字符串下发（`"reposts_count": "12"`），有时又真是数字；
//   2. 时间有两种口径（`"created_at": "Tue Aug 29 12:00:00 +0800 2026"` 与 `"2026-08-29"`，
//      详情页还有绝对时间）；
//   3. 正文含 HTML 实体与标签（`<br/>`、`&amp;`）。
// 快照测试（§8.1 契约快照）盯的就是这层的输入输出。

/// 宽松整数：Int / Double / String / 缺失 都能解，缺失按 0
struct LooseInt: Decodable, Sendable, Equatable {
    var value: Int

    init(_ value: Int = 0) {
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = 0
            return
        }
        if let int = try? container.decode(Int.self) {
            self.value = int
            return
        }
        if let double = try? container.decode(Double.self) {
            self.value = Int(double)
            return
        }
        if let string = try? container.decode(String.self) {
            // "1.2万" / "12" / "" 都可能出现
            if let exact = Int(string) {
                self.value = exact
                return
            }
            if string.hasSuffix("万"), let base = Double(string.dropLast()) {
                self.value = Int(base * 10000)
                return
            }
            if string.hasSuffix("亿"), let base = Double(string.dropLast()) {
                self.value = Int(base * 100_000_000)
                return
            }
            self.value = 0
            return
        }
        self.value = 0
    }
}

/// 宽松可选整数：区分"没有这个字段"与"值为 0"
struct LooseOptionalInt: Decodable, Sendable, Equatable {
    var value: Int?

    init(_ value: Int? = nil) {
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = nil
            return
        }
        if let int = try? container.decode(Int.self) {
            self.value = int
            return
        }
        if let string = try? container.decode(String.self) {
            self.value = Int(string)
            return
        }
        self.value = nil
    }
}

/// 宽松字符串：数字/布尔被塞进字符串字段是常态
struct LooseString: Decodable, Sendable, Equatable {
    var value: String?

    init(_ value: String? = nil) {
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = nil
            return
        }
        if let string = try? container.decode(String.self) {
            self.value = string
            return
        }
        if let int = try? container.decode(Int.self) {
            self.value = String(int)
            return
        }
        if let bool = try? container.decode(Bool.self) {
            self.value = bool ? "1" : "0"
        }
    }
}

/// 宽松布尔（`"1"` / `1` / `true` 混用）
struct LooseBool: Decodable, Sendable, Equatable {
    var value: Bool

    init(_ value: Bool = false) {
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = false
            return
        }
        if let bool = try? container.decode(Bool.self) {
            self.value = bool
            return
        }
        if let int = try? container.decode(Int.self) {
            self.value = int != 0
            return
        }
        if let string = try? container.decode(String.self) {
            self.value = ["1", "true", "yes"].contains(string.lowercased())
            return
        }
        self.value = false
    }
}

/// 微博时间解析（多口径容错）。解析不出来就 `nil`，由 UI 显示原文，不做假装有值。
struct WebDate: Decodable, Sendable, Equatable {
    var date: Date?
    var raw: String?

    init(date: Date?, raw: String? = nil) {
        self.date = date
        self.raw = raw
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            return
        }
        if let string = try? container.decode(String.self) {
            raw = string
            date = WebDate.parse(string)
            return
        }
        if let seconds = try? container.decode(Double.self) {
            date = Date(timeIntervalSince1970: seconds)
            raw = String(Int(seconds))
        }
    }

    /// 已知的三种格式；新增格式只动这里
    static func parse(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let epoch = Double(trimmed) {
            return Date(timeIntervalSince1970: epoch)
        }

        let formats = [
            "EEE MMM dd HH:mm:ss Z yyyy", // Tue Aug 29 12:00:00 +0800 2026（Web ajax 主流口径）
            "yyyy-MM-dd HH:mm:ss", // 详情页绝对时间
            "yyyy-MM-dd", // 仅日期
            "yyyy-MM-dd'T'HH:mm:ssXXXXX" // ISO 带冒号时区
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            if let parsed = formatter.date(from: trimmed) {
                return parsed
            }
        }
        return nil
    }

    /// 相对时间（Cell 用：1分钟前 / 今天 12:03 / 8月29日）
    @MainActor
    static func relative(_ date: Date?, raw: String?) -> String {
        guard let date else { return raw ?? "—" }
        let now = Date()
        let interval = now.timeIntervalSince(date)
        switch interval {
        case ..<60: return "刚刚"
        case ..<3600: return "\(Int(interval / 60))分钟前"
        case ..<86400: return "\(Int(interval / 3600))小时前"
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
                ? "M月d日 HH:mm" : "yyyy-MM-dd HH:mm"
            return formatter.string(from: date)
        }
    }
}

/// HTML 实体与标签清理（`NSAttributedString(html:)` 必须在主线程，故整体标 `@MainActor`）
@MainActor
enum HTMLText {
    /// 去掉 `<br/>` `<span>` 等标签并还原实体，只保留纯文本
    static func strip(_ html: String?) -> String {
        guard let html, !html.isEmpty else { return "" }
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(
                  data: data,
                  options: [.documentType: NSAttributedString.DocumentType.html,
                            .characterEncoding: String.Encoding.utf8.rawValue],
                  documentAttributes: nil) else {
            return html
        }
        return attributed.string
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
