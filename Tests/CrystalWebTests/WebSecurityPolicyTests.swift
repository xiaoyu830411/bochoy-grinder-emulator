import Foundation
import XCTest
@testable import CrystalWeb

final class WebSecurityPolicyTests: XCTestCase {
    private func request(
        host: String?,
        origin: String? = nil,
        authorization: String? = nil,
        target: String = "/api/snapshot"
    ) throws -> HTTPRequest {
        var text = "GET \(target) HTTP/1.1\r\n"
        if let host { text += "Host: \(host)\r\n" }
        if let origin { text += "Origin: \(origin)\r\n" }
        if let authorization { text += "Authorization: \(authorization)\r\n" }
        text += "\r\n"
        return try XCTUnwrap(HTTPRequestParser.parse(Data(text.utf8)))
    }

    func testLoopbackAcceptsOnlyExplicitLoopbackHostValues() throws {
        let policy = WebSecurityPolicy(bindHost: "127.0.0.1")
        for host in ["localhost", "localhost:8080", "127.0.0.1:8080", "[::1]:8080", "[::1]"] {
            XCTAssertNoThrow(try policy.validate(request: request(host: host)))
        }
        for host in [nil, "evil.example", "127.0.0.1.evil.example", "localhost@evil.example", "127.0.0.2:8080"] {
            XCTAssertThrowsError(try policy.validate(request: request(host: host))) { error in
                XCTAssertEqual((error as? WebSecurityError)?.status, 403)
                XCTAssertEqual((error as? WebSecurityError)?.message, "Forbidden Host")
            }
        }
    }

    func testSuppliedOriginMustExactlyMatchHostWithoutCredentialsOrPath() throws {
        let policy = WebSecurityPolicy(bindHost: "localhost")
        XCTAssertNoThrow(try policy.validate(request: request(
            host: "localhost:8080",
            origin: "http://localhost:8080"
        )))
        for origin in [
            "http://evil.example", "https://localhost:8080", "http://localhost:8080/path",
            "http://user@localhost:8080", "null",
        ] {
            XCTAssertThrowsError(try policy.validate(request: request(
                host: "localhost:8080",
                origin: origin
            ))) { error in
                XCTAssertEqual((error as? WebSecurityError)?.status, 403)
                XCTAssertEqual((error as? WebSecurityError)?.message, "Origin does not match Host")
            }
        }
    }

    func testNonLoopbackConfigurationRequiresNonemptyToken() {
        XCTAssertNoThrow(try WebSecurityPolicy(bindHost: "127.0.0.1").validateConfiguration())
        for host in ["0.0.0.0", "192.168.1.10", "::"] {
            XCTAssertThrowsError(try WebSecurityPolicy(bindHost: host).validateConfiguration())
            XCTAssertThrowsError(try WebSecurityPolicy(bindHost: host, token: " ").validateConfiguration())
            XCTAssertNoThrow(try WebSecurityPolicy(bindHost: host, token: "secret").validateConfiguration())
        }
    }

    func testBearerAndSSEQueryTokenRules() throws {
        let policy = WebSecurityPolicy(bindHost: "0.0.0.0", token: "secret")
        let host = "192.168.1.10:8080"
        XCTAssertNoThrow(try policy.validate(request: request(
            host: host,
            authorization: "Bearer secret"
        )))
        XCTAssertNoThrow(try policy.validate(
            request: request(host: host, target: "/api/events?token=secret"),
            allowsQueryToken: true
        ))
        for authorization in [nil, "Bearer wrong", "secret"] {
            XCTAssertThrowsError(try policy.validate(request: request(
                host: host,
                authorization: authorization
            ))) { error in
                XCTAssertEqual((error as? WebSecurityError)?.status, 401)
                XCTAssertFalse((error as? WebSecurityError)?.message.contains("secret") ?? true)
            }
        }
        XCTAssertThrowsError(try policy.validate(request: request(
            host: host,
            target: "/api/snapshot?token=secret"
        )))
        XCTAssertThrowsError(try policy.validate(
            request: request(host: host, authorization: "Bearer wrong", target: "/api/events?token=secret"),
            allowsQueryToken: true
        ))
    }

    func testStaticAssetsSkipAuthenticationButNotHostAndOriginChecks() throws {
        let policy = WebSecurityPolicy(bindHost: "0.0.0.0", token: "secret")
        XCTAssertNoThrow(try policy.validate(
            request: request(host: "192.168.1.10:8080"),
            requiresAuthentication: false
        ))
        XCTAssertThrowsError(try policy.validate(
            request: request(host: "192.168.1.10:8080", origin: "http://evil.example"),
            requiresAuthentication: false
        ))
    }
}
