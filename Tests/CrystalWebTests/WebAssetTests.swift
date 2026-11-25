import XCTest
@testable import CrystalWeb

final class WebAssetTests: XCTestCase {
    func testLoadsPackagedSingleSourceAssetsWithContentTypes() throws {
        for path in ["/", "/index.html"] {
            let asset = try XCTUnwrap(WebAssets.asset(forPath: path))
            XCTAssertFalse(asset.data.isEmpty)
            XCTAssertEqual(asset.contentType, "text/html; charset=utf-8")
        }
        let javascript = try XCTUnwrap(WebAssets.asset(forPath: "/app.js"))
        XCTAssertFalse(javascript.data.isEmpty)
        XCTAssertEqual(javascript.contentType, "text/javascript; charset=utf-8")
        let client = try XCTUnwrap(WebAssets.asset(forPath: "/sim-client.js"))
        XCTAssertFalse(client.data.isEmpty)
        XCTAssertEqual(client.contentType, "text/javascript; charset=utf-8")
        let css = try XCTUnwrap(WebAssets.asset(forPath: "/styles.css"))
        XCTAssertFalse(css.data.isEmpty)
        XCTAssertEqual(css.contentType, "text/css; charset=utf-8")
    }

    func testAssetAllowlistDoesNotExposeAPIOrArbitraryFiles() {
        for path in ["/api/snapshot", "/../Info.plist", "/Package.swift", "/unknown.js"] {
            XCTAssertNil(WebAssets.asset(forPath: path))
        }
    }
}
