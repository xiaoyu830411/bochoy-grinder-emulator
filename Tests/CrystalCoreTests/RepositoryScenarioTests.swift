import Foundation
import XCTest
@testable import CrystalCore

final class RepositoryScenarioTests: XCTestCase {
    func testAllShippedScenariosAreValid() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = root.appendingPathComponent("Scenarios", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        XCTAssertGreaterThanOrEqual(files.count, 7)
        for file in files {
            XCTAssertNoThrow(try Scenario.load(from: file), "invalid scenario: \(file.lastPathComponent)")
        }

        let defaultScenario = try Scenario.load(from: directory.appendingPathComponent("default.json"))
        XCTAssertEqual(defaultScenario.initialRegisters.mtRPM, 0)
        XCTAssertEqual(defaultScenario.initialRegisters.xdRPM, 0)
        XCTAssertEqual(defaultScenario.initialRegisters.tfAngle, 0)
        XCTAssertEqual(defaultScenario.initialRegisters.servoAngle, 830)
    }
}
