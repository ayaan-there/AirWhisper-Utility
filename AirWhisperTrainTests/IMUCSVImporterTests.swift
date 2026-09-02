import XCTest
@testable import AirWhisperTrain

final class IMUCSVImporterTests: XCTestCase {
    func testImporterUsesTheRawIMUColumnContract() {
        XCTAssertEqual(IMUCSVImporter.requiredColumns.count, 15)
        XCTAssertEqual(IMUCSVImporter.requiredColumns.first, "time")
        XCTAssertEqual(IMUCSVImporter.requiredColumns.last, "quaternionZ")
    }
}
