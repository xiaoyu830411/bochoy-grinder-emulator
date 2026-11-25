import Foundation

public struct WebAsset: Equatable, Sendable {
    public let data: Data
    public let contentType: String

    public init(data: Data, contentType: String) {
        self.data = data
        self.contentType = contentType
    }
}

public enum WebAssets {
    private static let resources: [String: (name: String, type: String)] = [
        "/": ("index.html", "text/html; charset=utf-8"),
        "/index.html": ("index.html", "text/html; charset=utf-8"),
        "/app.js": ("app.js", "text/javascript; charset=utf-8"),
        "/sim-client.js": ("sim-client.js", "text/javascript; charset=utf-8"),
        "/styles.css": ("styles.css", "text/css; charset=utf-8"),
    ]

    public static func asset(forPath path: String) -> WebAsset? {
        guard let resource = resources[path],
              let url = Bundle.module.url(forResource: resource.name, withExtension: nil),
              let data = try? Data(contentsOf: url) else { return nil }
        return WebAsset(data: data, contentType: resource.type)
    }
}
