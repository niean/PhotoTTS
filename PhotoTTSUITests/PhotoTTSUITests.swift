import XCTest

final class PhotoTTSUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        
        // 验证应用能正常启动，底导 TabBar 可见
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "底导 TabBar 应在启动后可见")
    }
    
    @MainActor
    func testLaunchPerformance() throws {
        throw XCTSkip("性能基准测试，按需手动执行")
        // if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
        //     measure(metrics: [XCTApplicationLaunchMetric()]) {
        //         XCUIApplication().launch()
        //     }
        // }
    }
}
