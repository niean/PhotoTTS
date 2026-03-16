import XCTest

/// App Store 自动化测试
/// 运行方式：通过 distribution/take_screenshots.sh 脚本在多设备上执行
///
/// 截图清单:
///   01_home     - 首页（含绘本列表）
///   02_make     - 制作页（拍照/选图制作界面）
///   03_message  - 消息页
///   04_me       - 我的页（设置页）
///   05_play     - 播放页（播放 "26.03.10 使用介绍"）
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
        let deviceName = UIDevice.current.name.replacingOccurrences(of: " ", with: "_")

        let makeTabForHome = app.tabBars.buttons["制作"]
        if makeTabForHome.waitForExistence(timeout: 3) {
            makeTabForHome.tap()
            sleep(2)  // 等待制作页加载
        }
        sleep(10)
        

        // 1. 首页截图（先点击制作 Tab 再返回首页，确保 Tab 栏状态正确）
        let homeTabForHome = app.tabBars.buttons["首页"]
        if homeTabForHome.waitForExistence(timeout: 3) {
            homeTabForHome.tap()
            sleep(3)  // 等待首页加载完成
            captureScreenshot(named: "01_home_\(deviceName)")
        }

        // 2. 制作页截图
        let makeTabButton = app.tabBars.buttons["制作"]
        if makeTabButton.waitForExistence(timeout: 5) {
            makeTabButton.tap()
            sleep(3)  // 等待制作页加载完成
            captureScreenshot(named: "02_make_\(deviceName)")
        }

        // 3. 消息页截图
        let messageTabButton = app.tabBars.buttons["消息"]
        if messageTabButton.waitForExistence(timeout: 3) {
            messageTabButton.tap()
            sleep(2)  // 等待消息页加载完成
            captureScreenshot(named: "03_message_\(deviceName)")
        }

        // 4. 我的页截图
        let meTabButton = app.tabBars.buttons["我的"]
        if meTabButton.waitForExistence(timeout: 3) {
            meTabButton.tap()
            sleep(2)  // 等待我的页加载完成
            captureScreenshot(named: "04_me_\(deviceName)")
        }

        // 5. 播放页截图（最后截图，防止干扰其他页面）- 点击 "26.03.10 使用介绍" 的播放按钮
        let homeTabButton = app.tabBars.buttons["首页"]
        if homeTabButton.waitForExistence(timeout: 3) {
            homeTabButton.tap()
            sleep(2)
        }
        
        let playButton = app.buttons["play.circle"].firstMatch
        if playButton.waitForExistence(timeout: 5) {
            playButton.tap()
            // 等待 PlayView 全屏展示并加载图片
            sleep(3)
            // 点击屏幕显示控制层（PlayView 默认隐藏叠层）
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
