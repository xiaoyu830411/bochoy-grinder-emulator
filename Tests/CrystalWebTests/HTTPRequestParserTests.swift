import Foundation
import XCTest
@testable import CrystalWeb

final class HTTPRequestParserTests: XCTestCase {
    func testParsesRequestLineNormalizedHeadersPathAndQuery() throws {
        let request = try XCTUnwrap(HTTPRequestParser.parse(Data(
            "GET /api/events?token=a%20b&x=1 HTTP/1.1\r\nHost: 127.0.0.1:8080\r\nX-Test: value\r\n\r\n".utf8
        )))
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.target, "/api/events?token=a%20b&x=1")
        XCTAssertEqual(request.path, "/api/events")
        XCTAssertEqual(request.queryValue("token"), "a b")
        XCTAssertEqual(request.queryValue("x"), "1")
        XCTAssertEqual(request.header("HOST"), "127.0.0.1:8080")
        XCTAssertEqual(request.header("x-test"), "value")
        XCTAssertEqual(request.body, Data())
    }

    func testParsesContentLengthBodyAtConfiguredLimit() throws {
        let body = Data(repeating: 0x41, count: 16_384)
        var data = Data("POST /api/control HTTP/1.1\r\nHost: localhost\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
        data.append(body)
        let request = try XCTUnwrap(HTTPRequestParser.parse(data))
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.body, body)
    }

    func testIncompleteHeadersOrBodyRemainIncomplete() throws {
        XCTAssertNil(try HTTPRequestParser.parse(Data("GET / HTTP/1.1\r\nHost: localhost\r\n".utf8)))
        XCTAssertNil(try HTTPRequestParser.parse(Data(
            "POST /api/control HTTP/1.1\r\nHost: localhost\r\nContent-Length: 2\r\n\r\n{".utf8
        )))
    }

    func testDeclaredOversizedBodyFailsBeforeBodyArrives() {
        XCTAssertThrowsError(try HTTPRequestParser.parse(Data(
            "POST /api/control HTTP/1.1\r\nHost: localhost\r\nContent-Length: 16385\r\n\r\n".utf8
        ))) { error in
            XCTAssertEqual((error as? HTTPParseError)?.status, 413)
        }
    }

    func testMalformedRequestContentLengthAndTransferEncodingAreRejected() {
        let malformed = [
            "GET / HTTP/1.0\r\n\r\n",
            "GET /\r\n\r\n",
            "GET / HTTP/1.1\r\nHost: localhost\r\nContent-Length: nope\r\n\r\n",
            "POST / HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n",
        ]
        for text in malformed {
            XCTAssertThrowsError(try HTTPRequestParser.parse(Data(text.utf8)), text) { error in
                XCTAssertEqual((error as? HTTPParseError)?.status, 400)
            }
        }
    }

    func testDuplicateSecurityHeadersAreRejected() {
        for header in ["Host", "Content-Length", "Authorization", "Origin"] {
            let value = header == "Content-Length" ? "0" : "value"
            let text = "GET / HTTP/1.1\r\n\(header): \(value)\r\n\(header): \(value)\r\n\r\n"
            XCTAssertThrowsError(try HTTPRequestParser.parse(Data(text.utf8))) { error in
                XCTAssertEqual((error as? HTTPParseError)?.status, 400)
            }
        }
    }

    func testOversizedHeadersAndPipelinedRequestsAreRejected() {
        let longValue = String(repeating: "x", count: 16_385)
        XCTAssertThrowsError(try HTTPRequestParser.parse(Data(
            "GET / HTTP/1.1\r\nX-Long: \(longValue)\r\n\r\n".utf8
        ))) { error in
            XCTAssertEqual((error as? HTTPParseError)?.status, 431)
        }
        XCTAssertThrowsError(try HTTPRequestParser.parse(Data(
            "GET / HTTP/1.1\r\nHost: localhost\r\n\r\nGET / HTTP/1.1\r\n\r\n".utf8
        ))) { error in
            XCTAssertEqual((error as? HTTPParseError)?.status, 400)
        }
    }
}
