import Foundation

/// 契约 JSON 载入工具（`Tests/**\/Fixtures` 随测试目标一起打进测试 bundle）
enum Fixtures {
    static func data(named name: String) throws -> Data {
        let bundle = Bundle(for: FixtureToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: "Fixtures", withExtension: "json") else {
            throw NSError(domain: "Fixtures", code: 404, userInfo: [NSLocalizedDescriptionKey: "找不到契约 \(name).json"])
        }
        return try Data(contentsOf: url)
    }

    static func decoded<T: Decodable>(_ type: T.Type, named name: String) throws -> T {
        try JSONDecoder().decode(type, from: data(named: name))
    }
}

/// 只为给 `Bundle(for:)` 一个类型锚点
private final class FixtureToken: NSObject {}
