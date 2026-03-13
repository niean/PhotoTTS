import XCTest

/// App Store 截图自动化测试
/// 运行方式：通过 distribution/take_screenshots.sh 脚本在多设备上执行
///
/// 截图清单:
///   01_home     - 首页（含绘本列表）
///   02_play     - 播放页（播放 "26.03.10 使用介绍"）
///   03_make     - 制作页（拍照/选图制作界面）
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

        // 等待首页加载完成（含缩略图异步加载）
        sleep(5)

        // 1. 首页截图
        captureScreenshot(named: "01_home_\(deviceName)")

        // 2. 制作页截图（在播放前切换，避免 PlayView 全屏返回后的状态干扰）
        let makeTabButton = app.tabBars.buttons["制作"]
        if makeTabButton.waitForExistence(timeout: 5) {
            makeTabButton.tap()
            sleep(3)  // 等待制作页加载完成
            captureScreenshot(named: "03_make_\(deviceName)")
        }

        // 切回首页，准备播放截图
        let homeTabButton = app.tabBars.buttons["首页"]
        if homeTabButton.waitForExistence(timeout: 3) {
            homeTabButton.tap()
            sleep(2)
        }

        // 3. 播放页截图 - 点击 "26.03.10 使用介绍" 的播放按钮
        let playButton = app.buttons["play.circle"].firstMatch
        if playButton.waitForExistence(timeout: 5) {
            playButton.tap()
            // 等待 PlayView 全屏展示并加载图片
            sleep(3)
            // 点击屏幕显示控制层（PlayView 默认隐藏叠层）
            let window = app.windows.firstMatch
            window.tap()
            sleep(1)
            captureScreenshot(named: "02_play_\(deviceName)")
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
