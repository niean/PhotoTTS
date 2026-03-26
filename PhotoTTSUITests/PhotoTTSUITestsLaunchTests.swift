import XCTest

final class PhotoTTSUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        throw XCTSkip("启动截图测试，按需手动执行")
        // let app = XCUIApplication()
        // app.launch()
        //
        // let screenshot = app.screenshot()
        // let attachment = XCTAttachment(screenshot: screenshot)
        // attachment.name = "Launch Screen"
        // attachment.lifetime = .keepAlways
        // add(attachment)
    }
}
