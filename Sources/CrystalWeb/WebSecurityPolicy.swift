import Foundation

public struct WebSecurityError: Error, Equatable, LocalizedError, Sendable {
    public let status: Int
    public let message: String

    public init(status: Int, message: String) {
        self.status = status
        self.message = message
    }

    public var errorDescription: String? { message }
}

public struct WebSecurityPolicy: Sendable {
    public let bindHost: String
    private let token: String?

    public init(bindHost: String, token: String? = nil) {
        self.bindHost = bindHost
        self.token = token
    }

    public var isLoopback: Bool {
        Self.isLoopbackHost(bindHost)
    }

    public func validateConfiguration() throws {
        if !isLoopback && token?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw WebSecurityError(
                status: 500,
                message: "CRYSTAL_WEB_TOKEN is required for non-loopback Web binding"
            )
        }
    }

    public func validate(
        request: HTTPRequest,
        allowsQueryToken: Bool = false,
        requiresAuthentication: Bool = true
    ) throws {
        try validateConfiguration()
        guard let host = request.header("host"), let normalizedHost = Self.normalizeHost(host) else {
            throw WebSecurityError(status: 403, message: "Forbidden Host")
        }
        if isLoopback && !Self.isLoopbackHost(normalizedHost) {
            throw WebSecurityError(status: 403, message: "Forbidden Host")
        }
        if let origin = request.header("origin") {
            guard Self.origin(origin, matches: normalizedHost) else {
                throw WebSecurityError(status: 403, message: "Origin does not match Host")
            }
        }
        guard requiresAuthentication, let token else { return }
        if let authorization = request.header("authorization") {
            guard authorization == "Bearer \(token)" else {
                throw WebSecurityError(status: 401, message: "Bearer authentication required")
            }
            return
        }
        if allowsQueryToken, request.queryValue("token") == token {
            return
        }
        throw WebSecurityError(status: 401, message: "Bearer authentication required")
    }

    private static func isLoopbackHost(_ text: String) -> Bool {
        guard let normalized = normalizeHost(text) else { return false }
        let host: String
        if normalized.hasPrefix("[") {
            guard let closing = normalized.firstIndex(of: "]") else { return false }
            host = String(normalized[normalized.index(after: normalized.startIndex)..<closing])
        } else {
            host = normalized.split(separator: ":").first.map(String.init) ?? normalized
        }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private static func normalizeHost(_ text: String) -> String? {
        guard !text.isEmpty, text == text.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.contains(where: { $0.isWhitespace || "/\\@?#".contains($0) }) else { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("[") {
            guard let closing = lower.firstIndex(of: "]") else { return nil }
            let address = lower[lower.index(after: lower.startIndex)..<closing]
            guard !address.isEmpty, !address.contains("[") else { return nil }
            let remainder = lower[lower.index(after: closing)...]
            guard remainder.isEmpty || validPortSuffix(String(remainder)) else { return nil }
            return "[\(address)]\(remainder)"
        }
        guard lower.filter({ $0 == ":" }).count <= 1 else { return nil }
        if let colon = lower.lastIndex(of: ":") {
            let host = lower[..<colon]
            let suffix = String(lower[colon...])
            guard !host.isEmpty, validPortSuffix(suffix) else { return nil }
        }
        return lower
    }

    private static func validPortSuffix(_ text: String) -> Bool {
        guard text.hasPrefix(":"), text.count > 1 else { return false }
        let digits = text.dropFirst()
        guard digits.allSatisfy(\.isNumber), let port = Int(digits) else { return false }
        return (1...65_535).contains(port)
    }

    private static func origin(_ text: String, matches normalizedHost: String) -> Bool {
        guard let components = URLComponents(string: text), components.scheme == "http",
              let originHost = components.host?.lowercased(), components.user == nil,
              components.password == nil, components.path.isEmpty, components.query == nil,
              components.fragment == nil else { return false }
        let authorityHost = originHost.contains(":") ? "[\(originHost)]" : originHost
        let authority = components.port.map { "\(authorityHost):\($0)" } ?? authorityHost
        return authority == normalizedHost
    }
}
