import XCTest
@testable import PhotoTTS

final class OCRTextProcessorTests: XCTestCase {
    func testProcessCollapsesSixDotsToThree() {
        XCTAssertEqual(OCRTextProcessor.process("等等......我们来了"), "等等...我们来了")
    }

    func testProcessCollapsesMultipleSixDotRuns() {
        XCTAssertEqual(OCRTextProcessor.process("一......二......三"), "一...二...三")
    }

    func testProcessKeepsExistingWhitespaceCleanup() {
        XCTAssertEqual(OCRTextProcessor.process("\n第一行\n\n\n第二行\n"), "第一行\n第二行")
    }
}
