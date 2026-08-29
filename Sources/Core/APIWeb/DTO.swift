import Foundation

// MARK: - Web 端 DTO（PLAN §5「`Core/APIWeb`：端点注册表 + DTO（`Codable`）骨架」）
//
// 规矩：
// 1. DTO 只描述"Web 回包长什么样"，不做 UI 语义翻译（那是 Cell/ViewModel 的事）；
// 2. 所有字段一律**可缺省**——Web 端字段消失是常态（R1），解码不许因为少个字段就整条失败；
// 3. 字段名变更只改本目录，配合 `Tests` 里的契约快照第一时间发现（§8.1）。

// MARK: 解码小工具

extension KeyedDecodingContainer {
    // 说明：`try? decode(...)` 已返回单层可选（`decode` 本身非可选返回），
    // 无需 `decodeIfPresent` + `?? nil` 的双层收敛；字段缺失 → decode 抛错 → `try?` → nil → 取默认值。

    /// 字段存在且能宽松解析才返回，否则给默认值（永不抛）
    func zwInt(_ key: K) -> Int {
        (try? decode(LooseInt.self, forKey: key))?.value ?? 0
    }

    func zwOptionalInt(_ key: K) -> Int? {
        (try? decode(LooseOptionalInt.self, forKey: key))?.value
    }

    func zwString(_ key: K) -> String? {
        if let direct = try? decode(String.self, forKey: key) {
            return direct
        }
        return (try? decode(LooseString.self, forKey: key))?.value
    }

    func zwBool(_ key: K) -> Bool {
        (try? decode(LooseBool.self, forKey: key))?.value ?? false
    }

    func zwOptionalBool(_ key: K) -> Bool? {
        (try? decode(LooseBool.self, forKey: key))?.value
    }

    func zwDate(_ key: K) -> WebDate? {
        try? decode(WebDate.self, forKey: key)
    }

    func zwURL(_ key: K) -> URL? {
        zwString(key).flatMap(WebURL.https)
    }

    /// 按优先级尝试多个 key，返回第一个能解析出的 https URL
    func zwFirstURL(_ keys: [K]) -> URL? {
        for key in keys {
            if let url = zwURL(key) {
                return url
            }
        }
        return nil
    }
}

/// Web 端图片域名给的是 `//wx1.sinaimg.cn/...` 或 `http://...`，统一到 https
enum WebURL {
    static func https(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return nil
        }
        if text.hasPrefix("//") {
            text = "https:" + text
        }
        if text.hasPrefix("http://") {
            text = "https" + text.dropFirst(4)
        }
        return URL(string: text)
    }
}

// MARK: 用户

struct WBUser: Decodable, Equatable, Sendable, Identifiable {
    var id: String
    var screenName: String
    var avatarURL: URL?
    var verified: Bool
    var verifiedReason: String?
    /// 认证图标（蓝 V / 金 V），UI 用来选素材
    var verifiedType: Int
    var followers: Int
    var follows: Int
    var statusCount: Int
    var bio: String?
    /// 我对TA的关注态（列表回包里常常没有 → `nil` 表示"未知"，UI 不许显示按钮态）
    var isFollowing: Bool?
    var profileURL: URL?

    private enum CodingKeys: String, CodingKey {
        case id, idstr
        case screenName = "screen_name"
        case avatarHD = "avatar_hd"
        case avatarLarge = "avatar_large"
        case avatarNormal = "avatar_normal"
        case profileImage = "profile_image_url"
        case avatarHDR = "profile_avatar_hd"
        case verified, verifiedType = "verified_type", verifiedReason = "verified_reason"
        case followersCount = "followers_count"
        case followCount = "follow_count"
        case statusesCount = "statuses_count"
        case description
        case following
        case profileURL = "profile_url"
    }

    init(
        id: String = "",
        screenName: String = "",
        avatarURL: URL? = nil,
        verified: Bool = false,
        verifiedReason: String? = nil,
        verifiedType: Int = -1,
        followers: Int = 0,
        follows: Int = 0,
        statusCount: Int = 0,
        bio: String? = nil,
        isFollowing: Bool? = nil,
        profileURL: URL? = nil) {
        self.id = id
        self.screenName = screenName
        self.avatarURL = avatarURL
        self.verified = verified
        self.verifiedReason = verifiedReason
        self.verifiedType = verifiedType
        self.followers = followers
        self.follows = follows
        self.statusCount = statusCount
        self.bio = bio
        self.isFollowing = isFollowing
        self.profileURL = profileURL
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.zwString(.idstr) ?? container.zwString(.id) ?? ""
        screenName = container.zwString(.screenName) ?? ""
        avatarURL = container.zwFirstURL([.avatarHD, .avatarLarge, .avatarHDR, .profileImage, .avatarNormal])
        verified = container.zwBool(.verified) || (container.zwOptionalInt(.verifiedType).map { $0 >= 0 } ?? false)
        verifiedType = container.zwOptionalInt(.verifiedType) ?? -1
        verifiedReason = container.zwString(.verifiedReason)
        followers = container.zwInt(.followersCount)
        follows = container.zwInt(.followCount)
        statusCount = container.zwInt(.statusesCount)
        bio = container.zwString(.description)
        isFollowing = container.zwOptionalBool(.following)
        profileURL = container.zwURL(.profileURL)
    }
}

// MARK: 微博

struct WBStatus: Decodable, Equatable, Sendable, Identifiable {
    /// `mid`（数字 ID，接口参数用）；缺失时退到 `id`
    var id: String
    /// `bid`（base62，跳转 weibo.com/{uid}/{bid} 的详情页用）
    var bid: String?
    var text: String
    var createdAt: WebDate?
    var user: WBUser?
    var source: String?
    var pics: [WBPicture]
    var video: WBVideo?
    var reposts: Int
    var comments: Int
    var attitudes: Int
    var isLongText: Bool
    /// 转发源微博（递归一层；微博转发链实测极少超过 2 层）。
    /// Swift 的 `struct` 不能直接内联持有自身（`WBStatus?` 仍是定长值 → 无限尺寸），
    /// 故经数组做一次堆间接；对外仍以 `WBStatus?` 呈现，调用方无感。
    private var retweetHolder: [WBStatus] = []
    var retweeted: WBStatus? {
        get { retweetHolder.first }
        set { retweetHolder = newValue.map { [$0] } ?? [] }
    }

    var topicNames: [String]
    var detailURL: URL?

    private enum CodingKeys: String, CodingKey {
        case id, mid, bid, text, createdAt = "created_at", user, source
        case pics, picIds = "pic_ids", picInfos = "pic_infos", thumbnail = "thumbnail_pic"
        case pageInfo = "page_info"
        case repostsCount = "reposts_count"
        case commentsCount = "comments_count"
        case attitudesCount = "attitudes_count"
        case isLongText, longText = "longTextContent"
        case retweetedStatus = "retweeted_status"
        case topicStructure = "topic_struct"
        case topicName = "topic_name"
        case url
    }

    init(
        id: String,
        bid: String? = nil,
        text: String = "",
        createdAt: WebDate? = nil,
        user: WBUser? = nil,
        source: String? = nil,
        pics: [WBPicture] = [],
        video: WBVideo? = nil,
        reposts: Int = 0,
        comments: Int = 0,
        attitudes: Int = 0,
        isLongText: Bool = false,
        retweeted: WBStatus? = nil,
        topicNames: [String] = [],
        detailURL: URL? = nil) {
        self.id = id
        self.bid = bid
        self.text = text
        self.createdAt = createdAt
        self.user = user
        self.source = source
        self.pics = pics
        self.video = video
        self.reposts = reposts
        self.comments = comments
        self.attitudes = attitudes
        self.isLongText = isLongText
        self.retweetHolder = retweeted.map { [$0] } ?? []
        self.topicNames = topicNames
        self.detailURL = detailURL
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.zwString(.mid) ?? container.zwString(.id) ?? ""
        bid = container.zwString(.bid)
        text = container.zwString(.text) ?? ""
        createdAt = container.zwDate(.createdAt)
        user = try? container.decode(WBUser.self, forKey: .user)
        source = container.zwString(.source)
        reposts = container.zwInt(.repostsCount)
        comments = container.zwInt(.commentsCount)
        attitudes = container.zwInt(.attitudesCount)
        isLongText = container.zwBool(.isLongText)
        detailURL = container.zwURL(.url)

        // 配图三种口径：pics 数组 / pic_infos 字典 / 单图 thumbnail_pic
        if let pics = try? container.decode([WBPicture].self, forKey: .pics), !pics.isEmpty {
            self.pics = pics
        } else if let infos = try? container.decode([String: WBPictureInfo].self, forKey: .picInfos) {
            self.pics = infos.values.compactMap(\.thumbnailOrMiddle)
        } else if let thumb = container.zwURL(.thumbnail) {
            self.pics = [WBPicture(url: thumb, type: .thumbnail)]
        } else {
            self.pics = []
        }

        // 视频藏在 page_info（type == "video"）
        if let info = try? container.decode(WBPageInfo.self, forKey: .pageInfo), info.isVideo {
            video = WBVideo(pageImageURL: info.pageImage, streamURL: info.streamURL, title: info.title)
        } else {
            video = nil
        }

        if let topics = try? container.decode([WBTopic].self, forKey: .topicStructure) {
            topicNames = topics.map(\.topicName).compactMap { $0 }
        } else {
            topicNames = []
        }

        // 转发源：优先结构体内的文本，其次顶层 text 去标签由 UI 层处理
        retweeted = try? container.decode(WBStatus.self, forKey: .retweetedStatus)
    }

    /// 用于时间线去重与游标推进
    var sortKey: Double {
        createdAt?.date?.timeIntervalSince1970 ?? 0
    }

    private struct WBTopic: Decodable, Sendable {
        var topicName: String?
        enum CodingKeys: String, CodingKey { case topicName = "topic_name" }
    }
}

// MARK: 配图

struct WBPicture: Decodable, Equatable, Sendable, Hashable {
    enum Kind: String, Sendable {
        case thumbnail
        case middle
        case large
    }

    var url: URL
    var type: Kind

    private enum CodingKeys: String, CodingKey {
        case url, thumbnail, bmiddle, largest, type, picId = "pic_id"
    }

    init(url: URL, type: Kind) {
        self.url = url
        self.type = type
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // m 站：`{url, type}`；weibo.com：`{thumbnail, bmiddle, largest}`
        if let direct = container.zwURL(.url) {
            url = direct
        } else if let large = container.zwURL(.largest) {
            url = large
        } else if let middle = container.zwURL(.bmiddle) {
            url = middle
        } else if let thumb = container.zwURL(.thumbnail) {
            url = thumb
        } else {
            throw APIError.decode(field: "picture.url", hint: "配图没有任何可用地址")
        }
        switch container.zwString(.type) {
        case "thumb": type = .thumbnail
        case "middle": type = .middle
        case "large": type = .large
        default: type = .middle
        }
    }

    /// 大图查看器用的放大地址（`thumbnail` → `bmiddle`/`largest` 的域名替换是 Web 端老规矩，
    /// 但改版风险高，故只在实测确认后再启用；当前按回包地址原样使用）
    var preferredForViewer: URL {
        url
    }
}

/// `pic_infos` 字典的值：`{pid, url: {thumbnail, bmiddle, largest}}`
private struct WBPictureInfo: Decodable, Sendable {
    var url: Nested
    struct Nested: Decodable, Sendable {
        var thumbnail: URL?
        var bmiddle: URL?
        var largest: URL?
        enum CodingKeys: String, CodingKey { case thumbnail, bmiddle, largest }
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            thumbnail = container.zwURL(.thumbnail)
            bmiddle = container.zwURL(.bmiddle)
            largest = container.zwURL(.largest)
        }
    }

    enum CodingKeys: String, CodingKey { case url }
    var thumbnailOrMiddle: WBPicture? {
        guard let target = url.largest ?? url.bmiddle ?? url.thumbnail else { return nil }
        return WBPicture(url: target, type: .middle)
    }
}

// MARK: 视频

struct WBVideo: Decodable, Equatable, Sendable, Hashable {
    var pageImageURL: URL?
    var streamURL: URL?
    var title: String?
}

/// `page_info`：视频/文章/直播共用容器，M0 只消化视频
private struct WBPageInfo: Decodable, Sendable {
    var type: String?
    var pageImage: URL?
    var urls: StreamURLs?
    var title: String?

    struct StreamURLs: Decodable, Sendable {
        var mp4720: URL?
        var mp4HD: URL?
        enum CodingKeys: String, CodingKey {
            case mp4720 = "mp4_720p_mp4"
            case mp4HD = "mp4_hd_url"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mp4720 = container.zwURL(.mp4720)
            mp4HD = container.zwURL(.mp4HD)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case pageImage = "page_image_url"
        case urls
        case title
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = container.zwString(.type)
        pageImage = container.zwURL(.pageImage)
        urls = try? container.decode(StreamURLs.self, forKey: .urls)
        title = container.zwString(.title)
    }

    var isVideo: Bool {
        type == "video" || type == "vinvoke"
    }

    var streamURL: URL? {
        urls?.mp4720 ?? urls?.mp4HD
    }
}

// MARK: 评论（M4 用；骨架先定字段）

struct WBComment: Decodable, Equatable, Sendable, Identifiable {
    var id: String
    var text: String
    var createdAt: WebDate?
    var user: WBUser?
    var likes: Int
    /// 被回复评论的 ID（楼中楼）
    var replyID: String?

    private enum CodingKeys: String, CodingKey {
        case id, mid, text, createdAt = "created_at", user
        case likeCount = "like_count"
        case replyID = "reply_id"
    }

    init(
        id: String,
        text: String = "",
        createdAt: WebDate? = nil,
        user: WBUser? = nil,
        likes: Int = 0,
        replyID: String? = nil) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.user = user
        self.likes = likes
        self.replyID = replyID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.zwString(.mid) ?? container.zwString(.id) ?? ""
        text = container.zwString(.text) ?? ""
        createdAt = container.zwDate(.createdAt)
        user = try? container.decode(WBUser.self, forKey: .user)
        likes = container.zwInt(.likeCount)
        replyID = container.zwString(.replyID)
    }
}

// MARK: 回包容器

/// weibo.com ajax 的统一信封：`{"ok":1,"data":…}`
struct WebEnvelope<Payload: Decodable>: Decodable {
    var ok: Int
    var data: Payload?
    var msg: String?

    enum CodingKeys: String, CodingKey { case ok, data, msg, message }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = container.zwInt(.ok)
        data = try? container.decode(Payload.self, forKey: .data)
        msg = container.zwString(.msg) ?? container.zwString(.message)
        if ok != 1, data == nil {
            throw APIError.business(code: ok, message: msg)
        }
    }
}

/// m.weibo.cn 的容器：`{"ok":1,"data":{"statuses":[…],"cardlistInfo":{…}}}`
struct WebContainer<Payload: Decodable>: Decodable {
    var ok: Int
    var data: Payload?

    enum CodingKeys: String, CodingKey { case ok, data }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = container.zwInt(.ok)
        data = try? container.decode(Payload.self, forKey: .data)
    }
}
