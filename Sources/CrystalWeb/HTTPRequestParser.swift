import Foundation

public struct HTTPParseError: Error, Equatable, LocalizedError, Sendable {
    public let status: Int
    public let message: String

    public init(status: Int, message: String) {
        self.status = status
        self.message = message
    }

    public var errorDescription: String? { message }
}

public struct HTTPRequest: Equatable, Sendable {
    public let method: String
    public let target: String
    private let headers: [String: String]
    public let body: Data

    init(method: String, target: String, headers: [String: String], body: Data) {
        self.method = method
        self.target = target
        self.headers = headers
        self.body = body
    }

    public var path: String {
        URLComponents(string: target)?.path ?? target
    }

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    public func queryValue(_ name: String) -> String? {
        URLComponents(string: target)?.queryItems?.first { $0.name == name }?.value
    }
}

public enum HTTPRequestParser {
    public static let maximumBodyBytes = 16_384
    public static let maximumHeaderBytes = 16_384
    private static let separator = Data([0x0d, 0x0a, 0x0d, 0x0a])

    public static func parse(
        _ data: Data,
        bodyLimit: Int = maximumBodyBytes
    ) throws -> HTTPRequest? {
        guard let separatorRange = data.range(of: separator) else {
            if data.count > maximumHeaderBytes {
                throw HTTPParseError(status: 431, message: "Request headers too large")
            }
            return nil
        }
        guard separatorRange.lowerBound <= maximumHeaderBytes else {
            throw HTTPParseError(status: 431, message: "Request headers too large")
        }
        let headerData = data.subdata(in: data.startIndex..<separatorRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw HTTPParseError(status: 400, message: "Request headers must be UTF-8")
        }
        let withoutLineBreaks = headerText.replacingOccurrences(of: "\r\n", with: "")
        guard !withoutLineBreaks.contains("\r"), !withoutLineBreaks.contains("\n") else {
            throw HTTPParseError(status: 400, message: "Malformed HTTP line endings")
        }
        var lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, parts[2] == "HTTP/1.1" else {
            throw HTTPParseError(status: 400, message: "Malformed HTTP/1.1 request line")
        }
        let target = String(parts[1])
        guard target.hasPrefix("/"), !target.contains("#"),
              target.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value != 0x7f }) else {
            throw HTTPParseError(status: 400, message: "Only origin-form request targets are supported")
        }
        guard lines.count <= 100 else {
            throw HTTPParseError(status: 431, message: "Too many request headers")
        }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else {
                throw HTTPParseError(status: 400, message: "Malformed request header")
            }
            let name = String(line[..<colon])
            guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
                throw HTTPParseError(status: 400, message: "Invalid request header name")
            }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard value.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7f }) else {
                throw HTTPParseError(status: 400, message: "Invalid request header value")
            }
            let key = name.lowercased()
            guard headers[key] == nil else {
                throw HTTPParseError(status: 400, message: "Duplicate request header: \(name)")
            }
            headers[key] = value
        }
        guard headers["transfer-encoding"] == nil else {
            throw HTTPParseError(status: 400, message: "Transfer-Encoding is not supported")
        }
        let contentLength: Int
        if let text = headers["content-length"] {
            guard !text.isEmpty, text.allSatisfy(\.isNumber), let parsed = Int(text), parsed >= 0 else {
                throw HTTPParseError(status: 400, message: "Invalid Content-Length")
            }
            contentLength = parsed
        } else {
            contentLength = 0
        }
        guard contentLength <= bodyLimit else {
            throw HTTPParseError(status: 413, message: "Request body exceeds 16 KB limit")
        }
        let bodyStart = separatorRange.upperBound
        let available = data.distance(from: bodyStart, to: data.endIndex)
        guard available >= contentLength else { return nil }
        guard available == contentLength else {
            throw HTTPParseError(status: 400, message: "Pipelined requests are not supported")
        }
        let bodyEnd = data.index(bodyStart, offsetBy: contentLength)
        return HTTPRequest(
            method: String(parts[0]),
            target: target,
            headers: headers,
            body: data.subdata(in: bodyStart..<bodyEnd)
        )
    }
}
