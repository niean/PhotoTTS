import XCTest

/// App Store 自动化测试
/// 运行方式：通过 distribution/take_screenshots.sh 脚本在多设备上执行
///
/// 截图清单:
///   01_home     - 首页（含绘本列表）
final class ScreenshotUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        // 禁用屏幕录制限制，确保截图能正确捕获
        app.launchArguments = ["-screenshotTesting", "true"]
        app.launch()
    }

    // MARK: - 截图入口

    @MainActor
    func testCaptureAllScreenshots() throws {
        // throw XCTSkip("App Store 截图测试，发版前通过 take-screenshots.sh 手动执行")
        let deviceName = UIDevice.current.name.replacingOccurrences(of: " ", with: "_")
        
        let makeTabForHome = app.tabBars.buttons["制作"]
        if makeTabForHome.waitForExistence(timeout: 3) {
            makeTabForHome.tap()
            sleep(2)
        }
        sleep(10)
        
        // 1. 首页截图
        let homeTabForHome = app.tabBars.buttons["首页"]
        if homeTabForHome.waitForExistence(timeout: 3) {
            homeTabForHome.tap()
            sleep(3)
            captureScreenshot(named: "01_home_\(deviceName)")
        }
        
        // 2. 制作页截图
        let makeTabButton = app.tabBars.buttons["制作"]
        if makeTabButton.waitForExistence(timeout: 5) {
            makeTabButton.tap()
            sleep(3)
            captureScreenshot(named: "02_make_\(deviceName)")
        }
        
        // 3. 管理页截图
        let manageTabButton = app.tabBars.buttons["管理"]
        if manageTabButton.waitForExistence(timeout: 3) {
            manageTabButton.tap()
            sleep(2)
            captureScreenshot(named: "03_manage_\(deviceName)")
        }
        
        // 4. 我的页截图
        let meTabButton = app.tabBars.buttons["我的"]
        if meTabButton.waitForExistence(timeout: 3) {
            meTabButton.tap()
            sleep(2)
            captureScreenshot(named: "04_me_\(deviceName)")
        }
        
        // 5. 播放页截图
        let homeTabButton = app.tabBars.buttons["首页"]
        if homeTabButton.waitForExistence(timeout: 3) {
            homeTabButton.tap()
            sleep(2)
        }
        
        let playButton = app.buttons["play.circle"].firstMatch
        if playButton.waitForExistence(timeout: 5) {
            playButton.tap()
            sleep(3)
            let window = app.windows.firstMatch
            window.tap()
            sleep(1)
            captureScreenshot(named: "05_play_\(deviceName)")
        }
    }

    // MARK: - 辅助方法

    private func captureScreenshot(named name: String) {
        let screenshot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("Screenshot captured: \(name)")
    }
}
